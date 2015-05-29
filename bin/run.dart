import "dart:async";
import "dart:convert";

import "package:dslink/client.dart";
import "package:dslink/responder.dart";
import "package:http/http.dart" as http;

http.Client client = new http.Client();

LinkProvider link;

main(List<String> args) async {
  link = new LinkProvider(args, "Weather-", command: "run", defaultNodes: {
    "Create_Tracker": {
      r"$is": "createTracker",
      r"$invokable": "write",
      r"$result": "values",
      r"$name": "Create Tracker",
      r"$params": [
        {
          "name": "city",
          "type": "string"
        }
      ]
    }
  }, profiles: {
    "createTracker": (String path) => new CreateTrackerNode(path),
    "deleteTracker": (String path) => new DeleteTrackerNode(path)
  }, encodePrettyJson: true);

  rootNode = link["/"];

  new Timer.periodic(weatherTickRate, (timer) async {
    await updateTrackers();
  });

  link.connect();
}

Duration weatherTickRate = new Duration(seconds: 10);

SimpleNode rootNode;

updateTrackers() async {
  for (SimpleNode node in rootNode.children.values) {
    if (node.getConfig(r"$invokable") != null) {
      continue;
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
    l("Temperature")..attributes["@unit"] = info["units"]["temperature"]..updateValue(info["temperature"]);
    l("Wind_Chill")..attributes["@unit"] = info["units"]["temperature"]..updateValue(info["wind chill"]);
    l("Wind_Speed")..attributes["@unit"] = info["units"]["speed"]..updateValue(info["wind speed"]);
    l("Wind_Direction").updateValue(info["wind direction"]);
    l("Humidity").updateValue(info["humidity"]);
    l("Pressure")..attributes["@unit"] = info["units"]["pressure"]..updateValue(info["pressure"]);
    l("Visibility")..attributes["@unit"] = info["units"]["distance"]..updateValue(info["visibility"]);
    try {
      l("Sunrise").updateValue(info["sunrise"]);
      l("Sunset").updateValue(info["sunset"]);
    } catch (e) {}
    SimpleNode forecast = node.getChild("Forecast");
    var fi = info["forecast"];

    for (var c in forecast.children.keys.toList()) {
      forecast.removeChild(c);
    }

    for (var x in fi) {
      link.addNode("${node.path}/Forecast/${x["day"]}", {
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
          "?value": x["high"]
        },
        "Low": {
          r"$type": "number",
          "?value": x["low"]
        }
      });
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
      return {};
    }

    link.addNode("/${id}", {
      r"$name": city,
      r"$city": city,
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

const String urlBase = "https://query.yahooapis.com/v1/public/yql";

String buildQuery(String city) {
  return 'select * from weather.forecast where woeid in (select woeid from geo.places(1) where text="${city}")';
}

Future<Map<String, dynamic>> queryWeather(String yql) async {
  try {
    yql = Uri.encodeComponent(yql);

    var url = "${urlBase}?q=${yql}&format=json&env=s${Uri.encodeComponent("store://datatables.org/alltableswithkeys")}";

    http.Response response = await client.get(url);

    var json = JSON.decode(response.body);

    return json["query"]["results"];
  } catch (e) {
    return null;
  }
}
