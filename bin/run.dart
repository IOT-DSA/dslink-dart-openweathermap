import "dart:async";
import "dart:convert";

import "package:dslink/client.dart";
import "package:dslink/responder.dart";
import "package:http/http.dart" as http;

http.Client client = new http.Client();

LinkProvider link;

main(List<String> args) async {
  link = new LinkProvider(args, "Weather-", command: "run", profiles: {
    "createTracker": (String path) => new CreateTrackerNode(path),
    "deleteTracker": (String path) => new DeleteTrackerNode(path)
  }, encodePrettyJson: true);

  rootNode = link["/"];

  link.addNode("/Create_Tracker", {
    r"$is": "createTracker",
    r"$invokable": "write",
    r"$result": "values",
    r"$name": "Create Tracker",
    r"$params": [
      {
        "name": "city",
        "type": "string"
      },
      {
        "name": "units",
        "type": "enum[Imperial,Metric]"
      }
    ]
  });

  new Timer.periodic(weatherTickRate, (timer) async {
    await updateTrackers();
  });

  updateTrackers();

  link.connect();
}

Duration weatherTickRate = new Duration(seconds: 10);

SimpleNode rootNode;

updateTrackers() async {
  for (SimpleNode node in rootNode.children.values) {
    if (node.getConfig(r"$invokable") != null) {
      continue;
    }

    var unitType = node.configs[r"$units_type"];
    if (unitType == null) {
      if (node.configs.containsKey(r"$temperature_units")) {
        unitType = node.configs[r"$temperature_units"] == "Fahrenheit" ? "Imperial" : "Metric";
      } else {
        unitType = "Imperial";
      }
    }
    var city = node.getConfig(r"$city");
    var info = await getWeatherInformation(city);
    if (info == null) {
      continue;
    }
    SimpleNode l(String name) {
      return node.getChild(name);
    }
    l("Condition").updateValue(info["condition"]);

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
    SimpleNode forecast = node.getChild("Forecast");
    var fi = info["forecast"];

    var names = [];

    for (var x in fi) {
      var dayName = x["day"];
      names.add(dayName);
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
      var p = "${node.path}/Forecast/${dayName}";
      var exists = (link.provider as SimpleNodeProvider).nodes.containsKey(p);

      if (exists) {
        var dateNode = link["${p}/Date"];
        var conditionNode = link["${p}/Condition"];
        var highNode = link["${p}/High"];
        var lowNode = link["${p}/Low"];
        dateNode.updateValue(x["date"]);
        conditionNode.updateValue(x["text"]);
        highNode.updateValue(high.left);
        lowNode.updateValue(low.left);
        highNode.configs[r"@unit"] = high.right;
        lowNode.configs[r"@unit"] = low.right;
      } else {
        link.addNode("${node.path}/Forecast/${dayName}", {
          "Date": {
            r"$type": "string",
            "?value": x["date"]
          },
          "Condition": {
            r"$type": "string",
            "?value": x["text"]
          },
          "High": {
            r"$type": "number",
            "?value": high.left,
            "@unit": high.right
          },
          "Low": {
            r"$type": "number",
            "?value": low.left,
            "@unit": low.right
          }
        });
      }
    }

    SimpleNode mn = link["${node.path}/Forecast"];
    for (var key in mn.children.keys.toList()) {
      if (!names.contains(key)) {
        link.removeNode("${mn.path}/${key}");
      }
    }
  }
}

class CreateTrackerNode extends SimpleNode {
  CreateTrackerNode(String path) : super(path);

  @override
  Object onInvoke(Map<String, dynamic> params) async {
    if (params["city"] == null) {
      return {};
    }

    var units = params["units"];
    var city = params["city"];
    Map data = await queryWeather(buildQuery(city));

    if (data == null) {
      return {};
    }

    var loc = data["channel"]["location"];

    if (loc == null) {
      return {};
    }

    var id = "${loc["city"]}-${loc["region"]}-${loc["country"]}";

    if ((link.provider as SimpleNodeProvider).nodes.containsKey("/${id}")) {
      link.removeNode("/${id}");
    }

    link.addNode("/${id}", {
      r"$name": city,
      r"$city": city,
      r"$units_type": units,
      "Condition": {
        r"$type": "string",
        "?value": "Unknown"
      },
      "Temperature": {
        r"$type": "number",
        "?value": null
      },
      "Wind_Chill": {
        r"$name": "Wind Chill",
        r"$type": "number",
        "?value": null
      },
      "Wind_Speed": {
        r"$name": "Wind Speed",
        r"$type": "number",
        "?value": null
      },
      "Humidity": {
        r"$type": "number",
        "?value": null
      },
      "Pressure": {
        r"$type": "number",
        "?value": null
      },
      "Visibility": {
        r"$type": "number",
        "?value": null
      },
      "Wind_Direction": {
        r"$name": "Wind Direction",
        r"$type": "number",
        "?value": null
      },
      "Sunrise": {
        r"$type": "string",
        "?value": null
      },
      "Sunset": {
        r"$type": "string",
        "?value": null
      },
      "Forecast": {
      },
      "Delete_Tracker": {
        r"$is": "deleteTracker",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": {},
        r"$name": "Delete Tracker"
      }
    });

    updateTrackers();

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

Future<Map<String, dynamic>> getWeatherInformation(cl) async {
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

Pair<num, String> convertToUnits(num input, String currentUnits, String target) {
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
  "°F->Metric": (num input) => new Pair((input - 32) * (5 / 9), "°C"),
  "°C->Imperial": (num input) => new Pair((input * (9 / 5)) + 32, "°F"),
  "mi->Metric": (num input) => new Pair(input / 0.62137, "km"),
  "km->Imperial": (num input) => new Pair(input * 0.62137, "mi"),
  "in->Metric": (num input) => new Pair(input * 2.54, "cm"),
  "cm->Imperial": (num input) => new Pair(input / 2.54, "in"),
  "mph->Metric": (num input) => new Pair(input * 1.609344, "kph"),
  "kph->Imperial": (num input) => new Pair(input / 0.621371192, "mph")
};

const String urlBase = "https://query.yahooapis.com/v1/public/yql";

String buildQuery(String city) {
  return 'select * from weather.forecast where woeid in (select woeid from geo.places(1) where text="${city}")';
}

Future<Map<String, dynamic>> queryWeather(String yql) async {
  try {
    yql = Uri.encodeComponent(yql);

    var url = "${urlBase}?q=${yql}&format=json&env=${Uri.encodeComponent("store://datatables.org/alltableswithkeys")}";

    http.Response response = await client.get(url);

    var json = JSON.decode(response.body);

    return json["query"]["results"];
  } catch (e) {
    return null;
  }
}
