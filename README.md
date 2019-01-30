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

This DSLink uses the [openweathermap API](https://openweathermap.org).

You will need to [register for an appId](https://home.agromonitoring.com/users/sign_up) before using this dslink 

If you find the city created is not at the same location as you expected, 
you can [search city here](https://openweathermap.org/find) and then create tracker with city code instead of city name.