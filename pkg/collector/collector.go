package collector

import (
	"context"
	"fmt"
	"reflect"
	"time"

	v1 "agones.dev/agones/pkg/apis/agones/v1"
	"agones.dev/agones/pkg/client/clientset/versioned"
	"agones.dev/agones/pkg/client/informers/externalversions"
	externalv1 "agones.dev/agones/pkg/client/informers/externalversions/agones/v1"
	"github.com/Octops/agones-event-broadcaster/pkg/events"
	"github.com/go-kit/log"
	"github.com/go-kit/log/level"
	"github.com/pkg/errors"
	"github.com/prometheus/common/model"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
)

type FleetCollector struct {
	logger        log.Logger
	client        *versioned.Clientset
	fleetInformer externalv1.FleetInformer
}

func NewFleetCollector(ctx context.Context, logger log.Logger, config *rest.Config, resyncPeriod time.Duration) (*FleetCollector, error) {
	agonesClient, err := versioned.NewForConfig(config)
	if err != nil {
		return nil, errors.Wrap(err, "could not create the agones api clientset")
	}

	agonesInformerFactory := externalversions.NewSharedInformerFactory(agonesClient, resyncPeriod)
	fleets := agonesInformerFactory.Agones().V1().Fleets()

	go agonesInformerFactory.Start(ctx.Done())

	collector := &FleetCollector{
		logger:        log.WithPrefix(logger, "component", "collector"),
		client:        agonesClient,
		fleetInformer: fleets,
	}

	if err := collector.HasSynced(ctx); err != nil {
		return nil, errors.Wrap(err, "Agones failed to sync cache")
	}

	return collector, nil
}

func (f *FleetCollector) BuildEnvelope(event events.Event) (*events.Envelope, error) {
	envelope := &events.Envelope{}

	envelope.AddHeader("event_type", event.EventType().String())
	envelope.Message = event.(events.Message)

	return envelope, nil
}

func (f *FleetCollector) SendMessage(envelope *events.Envelope) error {
	message := envelope.Message.(events.Message).Content()
	eventType := envelope.Header.Headers["event_type"]

	switch eventType {
	case "fleet.events.added":
		fleet := message.(*v1.Fleet)
		return f.reconcile(fleet)
	case "fleet.events.updated":
		msg := reflect.ValueOf(message)
		fleet := msg.Field(1).Interface().(*v1.Fleet)
		return f.reconcile(fleet)
	case "fleet.events.deleted":
		fleet := message.(*v1.Fleet)
		namespaced := fmt.Sprintf("%s/%s", fleet.Namespace, fleet.Name)
		level.Debug(f.logger).Log("msg", "fleet deleted", "fleet", namespaced, "event", eventType, "action", "nop")
	}

	return nil
}

func (f *FleetCollector) HasSynced(ctx context.Context) error {
	informer := f.fleetInformer.Informer()

	tryFunc := func() error {
		stopper, cancel := context.WithTimeout(ctx, time.Second*15)
		defer cancel()

		level.Info(f.logger).Log("msg", "waiting for Agones cache to sync")
		if !cache.WaitForCacheSync(stopper.Done(), informer.HasSynced) {
			return errors.New("timed out waiting for Agones cache to sync")
		}
		return nil
	}

	return withRetry(time.Second*5, 5, tryFunc)
}

func (f *FleetCollector) reconcile(fleet *v1.Fleet) error {
	namespaced := fmt.Sprintf("%s/%s", fleet.Namespace, fleet.Name)

	_, ok := fleet.Annotations["octops.io/ttl"]
	if !ok {
		level.Debug(f.logger).Log("msg", "ignoring fleet, ttl annotation is not present", "fleet", namespaced)
		return nil
	}

	label, ok := fleet.Annotations["octops.io/ttl"]
	if !ok {
		err := errors.Errorf("fleet %s does not contain the ttl annotation", namespaced)
		level.Error(f.logger).Log("err", err)
		return err
	}

	ttl, err := model.ParseDuration(label)
	if err != nil {
		err := errors.Errorf("fleet %s has a invalid ttl %s", namespaced, label)
		level.Error(f.logger).Log("err", err)
		return err
	}

	expire := fleet.CreationTimestamp.Add(time.Duration(ttl))
	if time.Now().Before(expire) {
		level.Debug(f.logger).Log("msg", "ignoring fleet, ttl is not expired", "fleet", namespaced, "ttl", expire)
		return nil
	}

	if err := f.client.AgonesV1().Fleets(fleet.Namespace).Delete(context.Background(), fleet.Name, metav1.DeleteOptions{}); err != nil {
		return errors.Wrapf(err, "failed to delete fleet %s", namespaced)
	}

	level.Info(f.logger).Log("msg", "fleet deleted", "fleet", namespaced)

	return nil
}

// withRetry will wait for the interval before calling the f function for a max number of retries.
func withRetry(interval time.Duration, maxRetries int, f func() error) error {
	var err error
	if maxRetries <= 0 {
		maxRetries = 1
	}

	for attempt := 1; attempt <= maxRetries; attempt++ {
		time.Sleep(interval)
		if err = f(); err == nil {
			return nil
		}
		continue
	}

	return errors.Wrapf(err, "retry failed after %d attempts", maxRetries)
}
