part of dslink.weather.entry_point;

List columns = [
  {'name': 'Time'},
  {'name': 'Condition'},
  {'name': 'Condition_Codes'},
  {'name': 'Description'},
  {'name': 'Icon'},
  {'name': 'Temp_Max'},
  {'name': 'Temp_Min'},
  {'name': 'Humidity'},
];

class Forecast16Node extends SimpleNode {
  Map<String, dynamic> cache;

  Forecast16Node(String path) : super(path);

  @override
  Object onInvoke(Map<String, dynamic> params) {
    if (cache != null) {
      var rows = [];
      for (Map<String, dynamic> d in cache['list']) {
        var weather = d['weather'][0];
        var codes = [];
        for (int i = 0; i < (d['weather'] as List).length; ++i) {
          codes.add(d['weather'][i]['id']);
        }
        rows.add([
          new DateTime.fromMillisecondsSinceEpoch(d['dt'] * 1000)
              .toUtc()
              .toIso8601String(),
          weather['main'],
          codes.join(','),
          weather['description'],
          buildIconUrl(weather['icon']),
          d['temp']['max'],
          d['temp']['min'],
          d['humidity'],
        ]);
      }
      return new SimpleTableResult(rows, columns);
    }
    return {};
  }

  void setCache(Map<String, dynamic> data) {
    if (data == null || data['list'] is! List) {
      cache = null;
      return;
    }
    cache = data;
  }
}

class Forecast5Node extends SimpleNode {
  Map<String, dynamic> cache;

  Forecast5Node(String path) : super(path);

  @override
  Object onInvoke(Map<String, dynamic> params) {
    if (cache != null) {
      var rows = [];
      if (params['Interval'] != 'daily') {
        for (Map<String, dynamic> d in cache['list']) {
          var weather = d['weather'][0];
          var codes = [];
          for (var weather in d['weather'] as List) {
            codes.add(weather['id']);
          }
          rows.add([
            new DateTime.fromMillisecondsSinceEpoch(d['dt'] * 1000)
                .toUtc()
                .toIso8601String(),
            weather['main'],
            codes.join(','),
            weather['description'],
            buildIconUrl(weather['icon']),
            d['main']['temp_max'],
            d['main']['temp_min'],
            d['main']['humidity'],
          ]);
        }
      } else {
        mergeWeather(parent.configs[r'$lon'], cache['list'], rows);
      }

      return new SimpleTableResult(rows, columns);
    }
    return {};
  }

  void setCache(Map<String, dynamic> data) {
    if (data == null || data['list'] is! List) {
      cache = null;
      return;
    }
    cache = data;
  }
}
