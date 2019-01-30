part of dslink.weather.entry_point;

const interval = const Duration(seconds: 60);
Timer loadingTimer;


ListQueue<SimpleNode> tasks = new ListQueue<SimpleNode>();

runTask() async {
  var skipped = 0;
  if (appid != null)
    while (tasks.isNotEmpty &&
            usedCapacity < maxCapacity && // can't send more request per minute
            skipped < tasks.length && // prevent dead loop
            usedCapacity * 10 < tasks.length // spread requests
        ) {
      var taskNode = tasks.removeFirst();
      if (taskNode) {
        if (taskNode.removed) {
          // node no longer exists
          // run the next task
          skipped++;
        } else {
          if (taskNode is ForecastNode) {
            await loadForecast(taskNode);
            tasks.addLast(taskNode);
          } else {
            await loadCurrent(taskNode);
            tasks.addLast(taskNode);
          }
        }
      }
    }
  usedCapacity = 0;
  loadingTimer = new Timer(interval, runTask);
}

RegExp cityCodeRegex = new RegExp(r'^\d{7}$');

queryCity(String city, String unit) async {
  if (city.contains(cityCodeRegex)) {
    // search by id
    return await queryWeather('${urlBase}?id=${city}&appid=${appid}');
  } else {
    return await queryWeather('${urlBase}?q=${city}&appid=${appid}');
  }
}

loadCurrent(SimpleNode node) async {
  var cityId = node.configs[r'$cityId'];
  if (cityId is! num) {
    return;
  }
  var unit = node.configs[r'$units'];
  if (unit != 'imperial') {
    unit = 'metric';
  }
  var query = buildQuery(node, 'weather');
  var data = await queryWeather('${urlBase}?id=${cityId}&appid=${appid}');
  updateCurrent(node, data);
}

updateCurrent(SimpleNode node, Map<String, dynamic> data) {
  SimpleNode c(String name) {
    return node.getChild(name);
  }
  c('Condition').updateValue(data['weather'][0]['main']);
  c('Condition_Code').updateValue(data['weather'][0]['id']);
  c('Icon').updateValue(data['weather'][0]['icon']);
  c('Description').updateValue(data['weather'][0]['description']);
  c('Temperature').updateValue(data['main']['temp']);
  c('Wind_Speed').updateValue(data['wind']['speed']);
  c('Wind_Direction').updateValue(data['wind']['deg']);
  c('Humidity').updateValue(data['main']['humidity']);
  c('Pressure').updateValue(data['main']['pressure']);
  c('Visibility').updateValue(data['visibility']);
  c('Sunrise').updateValue(data['sys']['sunrise']);
  c('Sunset').updateValue(data['sys']['sunset']);
}

loadForecast(SimpleNode node) async {
  var query = buildQuery(node, 'forecast');
}

const String urlBase = "https://api.openweathermap.org/data/2.5/weather";

buildQuery(SimpleNode node, String api) {
  var cityId = node.configs[r'$cityId'];
  if (cityId is! num) {
    return null;
  }
  var unit = node.configs[r'$units'];
  if (unit != 'imperial') {
    unit = 'metric';
  }
}

Future<Map<String, dynamic>> queryWeather(String url) async {
  if (url == null) {
    return null;
  }
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
