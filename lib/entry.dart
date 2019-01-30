library dslink.weather.entry_point;

import "dart:async";
import "dart:convert";
import "dart:io";
import 'dart:collection';

import "package:dslink/client.dart";
import "package:dslink/responder.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";

part "./forecast.dart";

part "./loader.dart";

HttpClient httpClient;

LinkProvider link;

String appid;
num maxCapacity = 60;
num usedCapacity = 0;

main(List<String> args) async {
  httpClient = new HttpClient();
  httpClient.badCertificateCallback = (a, b, c) => true;
  httpClient.maxConnectionsPerHost = 4;

  link = new LinkProvider(args, "Weather-",
      command: "run",
      profiles: {
        "createTracker": (String path) => new CreateTrackerNode(path),
        "setAppId": (String path) => new SetAppIdNode(path),
        "forecast": (String path) => new ForecastNode(path),
        "deleteTracker": (String path) => new DeleteTrackerNode(path)
      },
      encodePrettyJson: true);

  rootNode = link["/"];

  SimpleNode createTrackerNode = link.addNode("/Create_Tracker", {
    r"$is": "createTracker",
    r"$invokable": "write",
    r"$result": "values",
    r"$name": "Create Tracker",
    r"$params": [
      {"name": "city", "type": "string"},
      {"name": "units", "type": "enum[imperial,metric]"}
    ]
  });
  createTrackerNode.serializable = false;

  SimpleNode setAppidNode = link.addNode("/Set_AppId", {
    r"$is": "setAppId",
    r"$invokable": "config",
    r"$result": "values",
    r"$name": "Set AppId",
    r"$params": [
      {"name": "AppId", "type": "string"},
      {"name": "Request per Minutes", "type": "number", "default": 50}
    ]
  });
  setAppidNode.serializable = false;

  var root = link.getNode('/');

  if (root.configs.containsKey(r'$$appid') &&
      root.configs[r'$$appid'] is String) {
    appid = root.configs[r'$$appid'];
    root.attributes.remove(r'@%20get%20appId%20from%20url');
  } else {
    root.attributes[r'@%20get%20appId%20from%20url'] =
        "https://home.agromonitoring.com/users/sign_up";
  }
  if (root.configs.containsKey(r'$$capacity') &&
      root.configs[r'$$capacity'] is num) {
    maxCapacity = root.configs[r'$$capacity'];
  }

  setAppidNode.serializable = false;

  link.connect();

  initTasks();
}

Duration weatherTickRate = new Duration(minutes: 15);

SimpleNode rootNode;

updateTrackers__() async {
  for (SimpleNode node in rootNode.children.values) {
    await updateTracker__(node);
  }
}

updateTracker__(SimpleNode node) async {
  if (node.getConfig(r"$invokable") != null) {
    return;
  }

  var unitType = node.configs[r"$units_type"];
  if (unitType == null) {
    if (node.configs.containsKey(r"$temperature_units")) {
      unitType = node.configs[r"$temperature_units"] == "Fahrenheit"
          ? "imperial"
          : "metric";
    } else {
      unitType = "imperial";
    }
  }
  var city = node.getConfig(r"$city");
  var info = await getWeatherInformation__(city);
  if (info == null) {
    return;
  }
  SimpleNode l(String name) {
    return node.getChild(name);
  }

  l("Condition").updateValue(info["condition"]);

  try {
    l("Condition_Code").updateValue(info["condition-code"]);
  } catch (e) {}

  var tempNode = l("Temperature");
  var windChillNode = l("Wind_Chill");

  var gotTemperatureUnits = info["units"]["temperature"];
  var gotTemperature = info["temperature"];
  var gotWindChill = info["wind chill"];

  try {
    if (gotTemperature is String) {
      gotTemperature = num.parse(gotTemperature);
    }

    if (gotWindChill is String) {
      gotWindChill = num.parse(gotWindChill);
    }
  } catch (e) {}

  var useTemperatureUnits = "°${gotTemperatureUnits}";

  var temp = convertToUnits(gotTemperature, useTemperatureUnits, unitType);
  var windChill = convertToUnits(gotWindChill, useTemperatureUnits, unitType);

  tempNode.updateValue(temp.left);
  windChillNode.updateValue(windChill.left);
  tempNode.attributes["@unit"] = temp.right;
  windChillNode.attributes["@unit"] = windChill.right;

  var windSpeedNode = l("Wind_Speed");
  var visibilityNode = l("Visibility");
  var pressureNode = l("Pressure");
  var humidityNode = l("Humidity");

  humidityNode.updateValue(info["humidity"]);

  var gotWindSpeed = info["wind speed"];
  var gotVisibility = info["visibility"];
  var gotPressure = info["pressure"];

  try {
    gotWindSpeed = num.parse(gotWindSpeed);
    gotVisibility = num.parse(gotVisibility);
    gotPressure = num.parse(gotPressure);
  } catch (e) {}

  var speedUnit = info["units"]["speed"];
  var pressureUnit = info["units"]["pressure"];
  var distanceUnit = info["units"]["distance"];

  var windSpeed = convertToUnits(gotWindSpeed, speedUnit, unitType);
  var pressure = convertToUnits(gotPressure, pressureUnit, unitType);
  var visibility = convertToUnits(gotVisibility, distanceUnit, unitType);

  windSpeedNode.updateValue(windSpeed.left);
  windSpeedNode.configs["@unit"] = windSpeed.right;
  pressureNode.updateValue(pressure.left);
  pressureNode.configs["@unit"] = pressure.right;
  visibilityNode.updateValue(visibility.left);
  visibilityNode.configs["@unit"] = visibility.right;

  l("Wind_Direction").updateValue(info["wind direction"]);
  try {
    l("Sunrise").updateValue(info["sunrise"]);
    l("Sunset").updateValue(info["sunset"]);
  } catch (e) {}
  var fi = info["forecast"];

  var names = [];

  for (var x in fi) {
    var dayName = x["day"].toString();
    var dateName = x["date"].toString();
    names.add(dateName);
    var gotHigh = x["high"];
    var gotLow = x["low"];

    try {
      if (gotHigh is String) {
        gotHigh = num.parse(gotHigh);
      }

      if (gotLow is String) {
        gotLow = num.parse(gotLow);
      }
    } catch (e) {}

    var high = convertToUnits(gotHigh, useTemperatureUnits, unitType);
    var low = convertToUnits(gotLow, useTemperatureUnits, unitType);
    var p = "${node.path}/Forecast/${NodeNamer.createName(dateName)}";
    var exists = (link.provider as SimpleNodeProvider).hasNode(p);

    if (exists) {
      var dateNode = link["${p}/Date"];
      var conditionNode = link["${p}/Condition"];
      var conditionCodeNode = link["${p}/Condition_Code"];
      var highNode = link["${p}/High"];
      var lowNode = link["${p}/Low"];
      var dayNode = link["${p}/Day"];

      if (dateNode != null) {
        dateNode.updateValue(x["date"]);
      }

      if (conditionCodeNode != null) {
        conditionCodeNode.updateValue(x["code"]);
      }

      if (conditionNode != null) {
        conditionNode.updateValue(x["text"]);
      }

      if (lowNode != null) {
        lowNode.updateValue(low.left);
      }

      if (highNode != null) {
        highNode.configs[r"@unit"] = high.right;
      }

      if (lowNode != null) {
        lowNode.configs[r"@unit"] = low.right;
      }

      if (dayNode != null) {
        dayNode.updateValue(dayName);
      }
    } else {
      link.addNode(p, {
        "Day": {r"$type": "string", "?value": x["day"]},
        "Date": {r"$type": "string", "?value": x["date"]},
        "Condition": {r"$type": "string", "?value": x["text"]},
        "Condition_Code": {
          r"$name": "Condition Code",
          r"$type": "number",
          "?value": -1
        },
        "High": {r"$type": "number", "?value": high.left, "@unit": high.right},
        "Low": {r"$type": "number", "?value": low.left, "@unit": low.right}
      });
    }
  }

  SimpleNode mn = link["${node.path}/Forecast"];
  for (var key in mn.children.keys.toList()) {
    var name = NodeNamer.decodeName(key);

    if (!names.contains(name)) {
      link.removeNode("${mn.path}/${key}");
    }
  }
}

class SetAppIdNode extends SimpleNode {
  SetAppIdNode(String path) : super(path);

  @override
  Object onInvoke(Map<String, dynamic> params) async {
    if (params["AppId"] == null ||
        params["AppId"] is! String ||
        params["AppId"].length < 32) {
      return {};
    }
    appid = params["AppId"];
    this.parent.configs[r"$$appid"] = appid;
    this.parent.updateList(r"$$appid");

    if (params['Request per Minutes'] is num &&
        params['Request per Minutes'] > 0) {
      maxCapacity = params['Request per Minutes'];
    } else {
      maxCapacity = 60;
    }
    this.parent.configs[r"$$capacity"] = maxCapacity;
    this.parent.updateList(r"$$capacity");

    link.save();
  }
}

class CreateTrackerNode extends SimpleNode {
  CreateTrackerNode(String path) : super(path);

  @override
  Object onInvoke(Map<String, dynamic> params) async {
    if (params["city"] == null || params["units"] == null || appid == null) {
      return {};
    }

    var units = params["units"];
    var city = params["city"];
    Map data = await queryCity(city, units);

    if (data == null) {
      return {};
    }

    var id = "${data['name']}-${data['id']}";

    if ((link.provider as SimpleNodeProvider).nodes.containsKey("/${id}")) {
      link.removeNode("/${id}");
    }
    var isMetric = units != 'imperial';

    var node = link.addNode("/${id}", {
      r"$name": data['name'],
      r"$city": data['name'],
      r"$units_type": units,
      "Condition": {r"$type": "string"},
      "Condition_Code": {
        r"$name": "Condition Code",
        r"$type": "number",
      },
      "Description": {
        r"$type": "string",
      },
      "Icon": {
        r"$type": "string",
      },
      "Temperature": {r"$type": "number", "@unit": isMetric ? "°C" : "°F"},

      "Wind_Speed": {
        r"$name": "Wind Speed",
        r"$type": "number",
        "@unit": isMetric ? "kph" : "mph"
      },
      "Wind_Direction": {r"$name": "Wind Direction", r"$type": "number"},
      "Humidity": {r"$type": "number"},
      "Pressure": {r"$type": "number", "@unit": "hPa"},
      "Visibility": {r"$type": "number", "@unit": "m"},
      "Sunrise": {r"$type": "string"},
      "Sunset": {r"$type": "string"},
      "Forecast": {
        r"$is": "forecast",
        r"$invokable": "read",
        r"$result": "table",
        r"$name": "Forecast"
      },
      "Delete_Tracker": {
        r"$is": "deleteTracker",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": {},
        r"$name": "Delete Tracker"
      }
    });

    updateCurrent(node, data);
    loadForecast(node);

    link.save();

    return {};
  }
}

class DeleteTrackerNode extends SimpleNode {
  DeleteTrackerNode(String path) : super(path);

  @override
  Object onInvoke(Map<String, dynamic> params) {
    var p = path.split("/").take(2).join("/");
    link.removeNode(p);
    link.save();
    return {};
  }
}

void initTasks() {}

Future<Map<String, dynamic>> getWeatherInformation__(cl) async {
  Map info;
  if (cl is Map) {
    info = cl;
  } else {
    info = await queryWeather(buildQuery(cl));
  }

  if (info == null) {
    return null;
  }

  var c = info["channel"]["item"]["condition"];
  var wind = info["channel"]["wind"];
  var astronomy = info["channel"]["astronomy"];
  var at = info["channel"]["atmosphere"];

  return {
    "condition": c["text"],
    "condition-code": c["code"],
    "temperature": c["temp"],
    "sunrise": astronomy["sunrise"],
    "sunset": astronomy["sunset"],
    "wind speed": wind["speed"],
    "wind chill": wind["chill"],
    "wind direction": wind["direction"],
    "humidity": at["humidity"],
    "pressure": at["pressure"],
    "visibility": at["visibility"],
    "forecast": info["channel"]["item"]["forecast"],
    "units": info["channel"]["units"]
  };
}

Pair<num, String> convertToUnits(
    num input, String currentUnits, String target) {
  if (input is! num) {
    return new Pair(input, currentUnits);
  }

  var name = "${currentUnits}->${target}";
  if (conversions.containsKey(name)) {
    return conversions[name](input);
  }
  return new Pair(input, currentUnits);
}

class Pair<A, B> {
  final A left;
  final B right;

  Pair(this.left, this.right);
}

typedef Pair<num, String> Conversion(num input);

Map<String, Conversion> conversions = {
  "°F->metric": (num input) => new Pair((input - 32) * (5 / 9), "°C"),
  "°C->imperial": (num input) => new Pair((input * (9 / 5)) + 32, "°F"),
  "mi->metric": (num input) => new Pair(input / 0.62137, "km"),
  "km->imperial": (num input) => new Pair(input * 0.62137, "mi"),
  "in->metric": (num input) => new Pair(input * 2.54, "cm"),
  "cm->imperial": (num input) => new Pair(input / 2.54, "in"),
  "mph->metric": (num input) => new Pair(input * 1.609344, "kph"),
  "kph->imperial": (num input) => new Pair(input / 0.621371192, "mph")
};
