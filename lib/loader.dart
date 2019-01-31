part of dslink.weather.entry_point;

const interval = const Duration(seconds: 60);
Timer loadingTimer;

ListQueue<SimpleNode> tasks = new ListQueue<SimpleNode>();

String buildIconUrl(String name) {
  return "http://openweathermap.org/img/w/${name}.png";
}

runTask() async {
  var count = 0;
  if (appid != null)
    try {
      while (tasks.isNotEmpty &&
              usedCapacity <
                  maxCapacity && // can't send more request per minute
              count <= tasks.length && // prevent dead loop
              usedCapacity * 10 < tasks.length // spread requests
          ) {
        var taskNode = tasks.removeFirst();
        if (taskNode != null) {
          if (taskNode.removed) {
            // node no longer exists
            // run the next task
          } else {
            if (taskNode is Forecast5Node) {
              await loadForecast5(taskNode);
              tasks.addLast(taskNode);
            } else if (taskNode is Forecast16Node) {
              await loadForecast16(taskNode);
              tasks.addLast(taskNode);
            } else {
              await loadCurrent(taskNode);
              tasks.addLast(taskNode);
            }
            ++count;
          }
        }
      }
    } catch (e, stack) {
      logger.warning(e);
      logger.warning(stack);
    }

  usedCapacity = 0;
  loadingTimer = new Timer(interval, runTask);
}

addTask(SimpleNode node) {
  if (node != null) {
    tasks.addLast(node);
  }
}

RegExp cityCodeRegex = new RegExp(r'^\d{7}$');
RegExp latlongReg = new RegExp(r'^[\+\-]?\d+\.\d+,[\+\-]?\d+\.\d+$');

queryCity(String city, String unit) async {
  if (city.contains(latlongReg)) {
    var latlon = city.split(',');
    return await queryWeather(
        '${urlBase}weather?lat=${latlon[0]}&lon=${latlon[1]}&appid=${appid}&units=${unit}');
  } else if (city.contains(cityCodeRegex)) {
    // search by id
    return await queryWeather(
        '${urlBase}weather?id=${city}&appid=${appid}&units=${unit}');
  } else {
    return await queryWeather(
        '${urlBase}weather?q=${city}&appid=${appid}&units=${unit}');
  }
}

loadCurrent(SimpleNode node) async {
  var cityId = node.configs[r'$cityId'];
  if (cityId is! num) {
    return;
  }

  var query = buildQuery(node, node, 'weather');
  if (query == null) {
    return;
  }
  var data = await queryWeather(query);
  updateCurrent(node, data);
}

updateCurrent(SimpleNode node, Map<String, dynamic> data) {
  if (node == null) {
    return;
  }
  SimpleNode c(String name) {
    return node.getChild(name);
  }

  var unit = node.configs[r'$units_type'];
  if (data['visibility'] != null) {
    if (unit != 'imperial') {
      c('Visibility').updateValue(data['visibility'] * 0.001);
    } else {
      c('Visibility').updateValue(data['visibility'] * 0.00062137119);
    }
  } else {
    c('Visibility').updateValue(null);
  }

  c('Condition').updateValue(data['weather'][0]['main']);

  var codes = [];
  for (var d in data['weather']) {
    codes.add(d['id']);
  }
  c('Condition_Codes').updateValue(codes.join(','));
  c('Icon').updateValue(buildIconUrl(data['weather'][0]['icon']));
  c('Description').updateValue(data['weather'][0]['description']);
  c('Temperature').updateValue(data['main']['temp']);
  c('Wind_Speed').updateValue(data['wind']['speed']);
  c('Wind_Direction').updateValue(data['wind']['deg']);
  c('Humidity').updateValue(data['main']['humidity']);
  c('Pressure').updateValue(data['main']['pressure']);
  c('Sunrise').updateValue(
      new DateTime.fromMillisecondsSinceEpoch(data['sys']['sunrise'] * 1000)
          .toUtc()
          .toIso8601String());
  c('Sunset').updateValue(
      new DateTime.fromMillisecondsSinceEpoch(data['sys']['sunset'] * 1000)
          .toUtc()
          .toIso8601String());
}

loadForecast5(Forecast5Node node) async {
  if (node == null) {
    return;
  }

  var query = buildQuery(node.parent, node, 'forecast');
  if (query == null) {
    return;
  }
  var data = await queryWeather(query);
  node.setCache(data);
}

loadForecast16(Forecast16Node node) async {
  if (node == null) {
    return;
  }
  var query = buildQuery(node.parent, node, 'forecast/daily');
  if (query == null) {
    return;
  }
  query = '${query}&cnt=16';
  var data = await queryWeather(query);
  node.setCache(data);
}

const String urlBase = "https://api.openweathermap.org/data/2.5/";

buildQuery(SimpleNode cityNode, SimpleNode cacheNode, String api) {
  var cityId = cityNode.configs[r'$cityId'];
  if (cityId is! num) {
    return null;
  }
  var unit = cityNode.configs[r'$units_type'];
  if (unit != 'imperial') {
    unit = 'metric';
  }
  var now = new DateTime.now();
  try {
    var ts = cacheNode.configs[r'$updateTime'];
    if (ts is String) {
      var lastUpdateTime = DateTime.parse(ts);
      if (now.difference(lastUpdateTime) < const Duration(minutes: 15)) {
        // update no more than once every 15 minutes
        return null;
      }
    }
  } catch (e, stack) {
    logger.warning(e);
    logger.warning(stack);
  }
  cacheNode.configs[r'$updateTime'] = now.toUtc().toIso8601String();
  cacheNode.updateList(r'$updateTime');
  return '${urlBase}${api}?id=${cityId}&appid=${appid}&units=${unit}';
}

Future<Map<String, dynamic>> queryWeather(String url) async {
  if (url == null) {
    return null;
  }
  logger.fine('loading data: ${url}');
  try {
    var request = await httpClient.getUrl(Uri.parse(url));
    var response = await request.close();
    usedCapacity++;
    var json =
        JSON.decode(await response.transform(const Utf8Decoder()).join());

    return json;
  } catch (e) {
    return null;
  }
}
