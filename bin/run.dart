import "dart:async";
import "dart:convert";

import "package:dslink/client.dart";
import "package:dslink/responder.dart";
import "package:http/http.dart" as http;
import "package:crypto/crypto.dart";

http.Client client = new http.Client();

LinkProvider link;

main(List<String> args) async {
  link = new LinkProvider(args, "Weather-", command: "run", defaultNodes: {
    "Create Tracker": {
      r"$is": "createTracker",
      r"$invokable": "write",
      r"$result": "values",
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
  });

  if (link.link == null) return;

  rootNode = link.provider.getNode("/");

  new Timer.periodic(weatherTickRate, (timer) async {
    await updateTrackers();
  });

  link.connect();
}

Duration weatherTickRate = new Duration(seconds: 5);

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
    l("Temperature").updateValue(info["temperature"]);
    l("Wind_Chill").updateValue(info["wind chill"]);
    l("Wind_Speed").updateValue(info["wind speed"]);
    l("Wind_Direction").updateValue(info["wind direction"]);
    l("Humidity").updateValue(info["humidity"]);
    l("Pressure").updateValue(info["pressure"]);
    l("Visibility").updateValue(info["visibility"]);
    SimpleNode forecast = node.getChild("Forecast");
    var fi = info["forecast"];

    for (var c in forecast.children.keys.toList()) {
      forecast.removeChild(c);
    }

    for (var x in fi) {
      link.provider.addNode("${node.path}/Forecast/${x["day"]}", {
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
  Object onInvoke(Map<String, dynamic> params) {
    if (params["city"] == null) {
      return {};
    }

    var city = params["city"];
    var id = CryptoUtils.bytesToBase64(city.codeUnits);

    link.provider.addNode("/${id}", {
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
      "Forecast": {
      },
      "Delete Tracker": {
        r"$is": "deleteTracker",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": {}
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
    link.provider.removeNode(p);
    link.save();
    return {};
  }
}

Future<Map<String, dynamic>> getWeatherInformation(String city) async {
  var info = await queryWeather(buildQuery(city));
  if (info == null) {
    return null;
  }

  var c = info["channel"]["item"]["condition"];
  var wind = info["channel"]["wind"];
  var at = info["channel"]["atmosphere"];

  return {
    "condition": c["text"],
    "temperature": c["temp"],
    "wind speed": wind["speed"],
    "wind chill": wind["chill"],
    "wind direction": wind["direction"],
    "humidity": at["humidity"],
    "pressure": at["pressure"],
    "visibility": at["visibility"],
    "forecast": info["channel"]["item"]["forecast"]
  };
}

String buildQuery(String city) {
  return 'select * from weather.forecast where woeid in (select woeid from geo.places(1) where text="${city}")';
}

Future<Map<String, dynamic>> queryWeather(String yql) async {
  try {
    yql = Uri.encodeComponent(yql);

    var url = "https://query.yahooapis.com/v1/public/yql?q=${yql}&format=json&env=${Uri.encodeComponent("store://datatables.org/alltableswithkeys")}";
    http.Response response = await client.get(url);

    var json = JSON.decode(response.body);

    return json["query"]["results"];
  } catch (e) {
    return null;
  }
}
