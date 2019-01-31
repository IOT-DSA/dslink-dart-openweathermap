# Weather DSLink

A DSLink for Weather Information.
Based on [openweathermap API](https://openweathermap.org).

## Concepts

### Trackers

A tracker is simply a node that has a city name attached. It contains information about the current conditions.

## Usage

To create a tracker, use the `Create Tracker` action on the link. To delete a tracker, use the `Delete Tracker` action on the tracker node.
#### Add App ID
You will need to [register for an appId](https://home.agromonitoring.com/users/sign_up) before using this dslink 

#### Create Tracker

* To help the dslink find the city, please add 2 characters county code after city name, i.e. : `Oakland,US`
* You can also use the lat,long coordinates of the city instead of city name, i.e. : `37.3382,-121.8863`
  * you can find the lat long of your city at [latlong.net](https://www.latlong.net)
