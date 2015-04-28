# Weather DSLink

A DSLink for Weather Information.

## Concepts

### Trackers

A tracker is simply a node that has a city name attached. It contains information about the current conditions, as well as a weekly forecast.

## Usage

```bash
pub get
dart bin/run.dart
```

To create a tracker, use the `Create Tracker` action on the link. To delete a tracker, use the `Delete Tracker` action on the tracker node.

## Internals

This DSLink uses the [Yahoo Weather API](https://developer.yahoo.com/weather/).
