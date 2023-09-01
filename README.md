# Octops Fleet Garbage Collector

The fleet garbage collector controller deletes Agones Fleets based on a TTL that is passed as an annotation.

In cases where a FleetAutoscaler is present, and it is associated to the Fleet being watched, it will be deleted together with the Fleet.

Check https://agones.dev/site/docs/reference/fleetautoscaler/ for more information about FleetAutoscalers
```yaml
apiVersion: "autoscaling.agones.dev/v1"
kind: FleetAutoscaler
metadata:
  name: fleet-autoscaler-example
spec:
  fleetName: simple-game-server #Used by Agones to manage a Fleet
```

## Deploy

```bash
$ kubectl apply -f https://github.com/Octops/octops-fleet-gc/blob/main/deploy/install.yaml
```

### Run Arguments
```
--sync-period=15s #Sync period interval when events are not triggered
--max-concurrent=5 #maximum number of concurrent Reconciles which can be run
--debug #remove this arg to make it less verbose
```

## Required Fleet Annotation

Add the `octops.io/ttl` annotation to the Fleet like the example below.

```yaml
apiVersion: "agones.dev/v1"
kind: Fleet
metadata:
  name: simple-game-server
  annotations:
    octops.io/ttl: 2m #Valid time units are "ns", "us" (or "µs"), "ms", "s", "m", "h", "d", "w", "y".
spec:
  replicas: 2
  template:
    spec:
      ports:
        - name: default
          containerPort: 7654
      template:
        spec:
          containers:
            - name: simple-game-server
              image: us-docker.pkg.dev/agones-images/examples/simple-game-server:0.17
              resources:
                requests:
                  memory: "64Mi"
                  cpu: "20m"
                limits:
                  memory: "64Mi"
                  cpu: "20m"
```
