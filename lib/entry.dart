library dslink.weather.entry_point;

import "dart:async";
import "dart:convert";
import "dart:io";
import 'dart:collection';

import "package:dslink/client.dart";
import "package:dslink/responder.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";
import "package:dslink/common.dart";

part "./forecast.dart";

part "./loader.dart";

part "./algorithm.dart";

HttpClient httpClient;

LinkProvider link;

String appid;

// how many requests per minute
num maxCapacity = 60;
// requests already used in previous minute
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
        "forecast5": (String path) => new Forecast5Node(path),
        "forecast16": (String path) => new Forecast16Node(path),
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
      {"name": "units", "type": "enum[imperial,metric]", "default": "imperial"},
      {
        "name": "forecast",
        "type": "enum[5days,16days,none]",
        "default": "5days"
      }
    ]
  });
  createTrackerNode.serializable = false;

  SimpleNode setAppidNode = link.addNode("/Set_AppId", {
    r"$is": "setAppId",
    r"$invokable": "config",
    r"$result": "values",
    r"$name": "Set AppId",
    r"$params": [
      {"name": "appid", "type": "string"},
      {"name": "requests per minute", "type": "number", "default": 50}
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

SimpleNode rootNode;

class SetAppIdNode extends SimpleNode {
  SetAppIdNode(String path) : super(path);

  @override
  Object onInvoke(Map<String, dynamic> params) async {
    if (params["appid"] == null ||
        params["appid"] is! String ||
        params["appid"].length < 32) {
      return new DSError("invalidParameter", msg: "invalid AppId");
    }
    appid = params["appid"];
    this.parent.configs[r"$$appid"] = appid;
    this.parent.updateList(r"$$appid");

    if (params["requests per minute"] is num &&
        params["requests per minute"] > 0) {
      maxCapacity = params['Request per Minute'];
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
    if (appid == null) {
      return new DSError("failed", msg: "AppId not set");
    }
    if (params["city"] == null || params["units"] == null) {
      return DSError.INVALID_PARAMETER;
    }
    var forecast = params["forecast"];
    var units = params["units"];
    var city = params["city"];
    Map data = await queryCity(city, units);

    if (data == null || !data.containsKey('name') || !data.containsKey('id')) {
      return new DSError("failed", msg: "City not found");
    }
    if (forecast != '16days' && forecast != '5days') {
      forecast = 'none';
    }

    var id = "${data['name']}-${data['id']}";

    if ((link.provider as SimpleNodeProvider).nodes.containsKey("/${id}")) {
      link.removeNode("/${id}");
    }
    var isMetric = units != 'imperial';
    var nodeData = {
      r"$cityId": data['id'],
      r"$name": data['name'],
      r"$city": data['name'],
      r"$country": data['sys']['country'],
      r"$lat": data['coord']['lat'],
      r"$lon": data['coord']['lon'],
      r"$units_type": units,
      "Condition": {r"$type": "string"},
      "Condition_Codes": {
        r"$name": "Condition Codes",
        r"$type": "string",
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
      "Visibility": {r"$type": "number", "@unit": isMetric ? "km" : "mi"},
      "Sunrise": {r"$type": "string"},
      "Sunset": {r"$type": "string"},
      "Delete_Tracker": {
        r"$is": "deleteTracker",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": {},
        r"$name": "Delete Tracker"
      }
    };
    if (forecast != 'none') {
      nodeData['Forecast5'] = {
        r"$is": "forecast5",
        r"$invokable": "read",
        r"$result": "table",
        r"$name": "Forecast 5 Days",
        r"$params": [
          {"name": "Interval", "type": "enum[3hours,daily]"}
        ]
      };
      if (forecast == '16days') {
        nodeData['Forecast16'] = {
          r"$is": "forecast16",
          r"$invokable": "read",
          r"$result": "table",
          r"$name": "Forecast 16 Days"
        };
      }
    }
    var node = link.addNode("/${id}", nodeData);

    updateCurrent(node, data);
    loadForecast5(node.getChild('Forecast5'));
    loadForecast16(node.getChild('Forecast16'));
    link.save();

    addTask(node);
    addTask(node.getChild('Forecast5'));
    addTask(node.getChild('Forecast16'));
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

void initTasks() {
  void restartTask(SimpleNode node) {
    if (node != null) {
      node.configs.remove(r'$updateTime');
      addTask(node);
    }
  }

  rootNode.children.forEach((key, node) {
    if (node is SimpleNode && node.configs.containsKey(r'$cityId')) {
      restartTask(node);
      restartTask(node.getChild('Forecast5'));
      restartTask(node.getChild('Forecast16'));
    }
  });

  // add dummy node to expand the task queue, so the initial loading can handler more data
  var dummyNode = new SimpleNode('dummy node remove later');
  dummyNode.removed = true;
  var target_size = tasks.length * 10;
  if (target_size > maxCapacity * 5) {
    // use no more than half of maxCapacity on the first run
    target_size = maxCapacity * 5;
  }
  while (tasks.length < target_size) {
    addTask(dummyNode);
  }
  runTask();
}
