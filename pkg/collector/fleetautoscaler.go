package collector

import (
	autoscaling "agones.dev/agones/pkg/apis/autoscaling/v1"
	"github.com/Octops/agones-event-broadcaster/pkg/events"
)

var (
	FleetAutoscalerEventAdded   FleetAutoscalerEventType = "fleetautoscaler.events.added"
	FleetAutoscalerEventUpdated FleetAutoscalerEventType = "fleetautoscaler.events.updated"
	FleetAutoscalerEventDeleted FleetAutoscalerEventType = "fleetautoscaler.events.deleted"
)

type FleetAutoscalerEventType string

// FleetAutoscalerEvent is the data structure for reconcile events associated with Agones FleetAutoscaler
// It holds the event source (OnAdd, OnUpdate, OnDelete) and the event type (Added, Updated, Deleted).
type FleetAutoscalerEvent struct {
	Source         events.EventSource       `json:"source"`
	Type           FleetAutoscalerEventType `json:"type"`
	events.Message `json:"message"`
}

func init() {
	events.RegisterEventFactory(&autoscaling.FleetAutoscaler{}, FleetAutoscalerAdded, FleetAutoscalerUpdated, FleetAutoscalerDeleted)
}

// FleetAutoscalerAdded is the data structure for reconcile events of type Add
func FleetAutoscalerAdded(message events.Message) events.Event {
	return &FleetAutoscalerEvent{
		Source:  events.EventSourceOnAdd,
		Type:    FleetAutoscalerEventAdded,
		Message: message,
	}
}

// FleetAutoscalerUpdated is the data structure for reconcile events of type Update
func FleetAutoscalerUpdated(message events.Message) events.Event {
	return &FleetAutoscalerEvent{
		Source:  events.EventSourceOnUpdate,
		Type:    FleetAutoscalerEventUpdated,
		Message: message,
	}
}

// FleetAutoscalerDeleted is the data structure for reconcile events of type Delete
func FleetAutoscalerDeleted(message events.Message) events.Event {
	return &FleetAutoscalerEvent{
		Source:  events.EventSourceOnDelete,
		Type:    FleetAutoscalerEventDeleted,
		Message: message,
	}
}

// EventType returns the type of the reconcile event for a FleetAutoscaler.
// For example: Added, Updated, Deleted
func (t *FleetAutoscalerEvent) EventType() events.EventType {
	return events.EventType(t.Type)
}

// EventSource return the event source that generated the event.
// For example: OnAdd, OnUpdate, OnDelete
func (t *FleetAutoscalerEvent) EventSource() events.EventSource {
	return t.Source
}

// String is a helper method that returns the string version of a FleetAutoscalerEventType
func (t FleetAutoscalerEventType) String() string {
	return string(t)
}
