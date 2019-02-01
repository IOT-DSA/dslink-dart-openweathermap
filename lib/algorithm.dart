part of dslink.weather.entry_point;

Map<int, int> codePriority = {
  // Group2xx: Thunderstorm

  200: 7000, //	thunderstorm with light rain	 11d
  201: 7010, //	thunderstorm with rain	 11d
  202: 7020, //	thunderstorm with heavy rain	 11d
  210: 7100, //	light thunderstorm	 11d
  211: 7110, //	thunderstorm	 11d
  212: 7120, //	heavy thunderstorm	 11d
  221: 7210, //	ragged thunderstorm	 11d
  230: 7300, //	thunderstorm with light drizzle	 11d
  231: 7310, //	thunderstorm with drizzle	 11d
  232: 7320, //	thunderstorm with heavy drizzle	 11d

// Group3xx: Drizzle

  300: 3000, //	light intensity drizzle	 09d
  301: 3010, //	drizzle	 09d
  302: 3020, //	heavy intensity drizzle	 09d
  310: 3100, //	light intensity drizzle rain	 09d
  311: 3110, //	drizzle rain	 09d
  312: 3120, //	heavy intensity drizzle rain	 09d
  313: 3130, //	shower rain and drizzle	 09d
  314: 3140, //	heavy shower rain and drizzle	 09d
  321: 3150, //	shower drizzle	 09d

// Group5xx: Rain

  500: 5000, //	light rain	 10d
  501: 5010, //	moderate rain	 10d
  502: 5020, //	heavy intensity rain	 10d
  503: 5030, //	very heavy rain	 10d
  504: 5040, //	extreme rain	 10d
  511: 5110, //	freezing rain	 13d
  520: 5200, //	light intensity shower rain	 09d
  521: 5210, //	shower rain	 09d
  522: 5220, //	heavy intensity shower rain	 09d
  531: 5310, //	ragged shower rain	 09d

// Group6xx: Snow

  600: 6000, //	light snow	 13d
  601: 6010, //	snow	 13d
  602: 6020, //	heavy snow	 13d
  611: 6110, //	sleet	 13d
  612: 6120, //	shower sleet	 13d
  615: 6150, //	light rain and snow	 13d
  616: 6160, //	rain and snow	 13d
  620: 6200, //	light shower snow	 13d
  621: 6210, //	shower snow	 13d
  622: 6220, //	heavy shower snow	 13d

// Group7xx: Atmosphere

  701: 1500, //	mist	 50d
  711: 1600, //	smoke	 50d
  721: 1700, //	haze	 50d
  731: 3500, //	sand, dust whirls	 50d
  741: 1800, //	fog	 50d
  751: 3600, //	sand	 50d
  761: 3700, //	dust	 50d
  762: 5500, //	volcanic ash	 50d
  771: 5600, //	squalls	 50d
  781: 9000, //	tornado	 50d

// Group800: Clear

  800: 1000, //	clear sky	 01d  01n

// Group80x: Clouds

  801: 950, //	few clouds	 02d  02n
  802: 960, //	scattered clouds	 03d  03n
  803: 1300, //	broken clouds	 04d  04n
  804: 1400, //	overcast clouds	 04d  04n
};

mergeWeather(num lon, List<Map<String, dynamic>> data, List output) {
  num tz = lon * 12 / 180; // estimate tz based on longitude
  num tzoff = (tz * 3600000).round();
  String currentDate = null;
  List currentGroup;
  List<List> groups = [];

  for (Map<String, dynamic> d in data) {
    String ts = new DateTime.fromMillisecondsSinceEpoch(d['dt'] * 1000 + tzoff)
        .toUtc()
        .toIso8601String()
        .substring(0, 10);

    if (currentDate == ts) {
      currentGroup.add(d);
    } else {
      currentDate = ts;
      currentGroup = [d];
      groups.add(currentGroup);
    }
  }
  for (var group in groups) {
    if (group.length > 5) {
      String ts =
          new DateTime.fromMillisecondsSinceEpoch(group[0]['dt'] * 1000 + tzoff)
              .toUtc()
              .toIso8601String()
              .substring(0, 10);

      num temp_max = double.NEGATIVE_INFINITY;
      num temp_min = double.INFINITY;
      num humiditySum = 0.0;
      Set<num> codes = new Set<num>();
      int priority = -1;
      Map<String, dynamic> mainWeather;

      for (Map<String, dynamic> d in group) {
        var weather = d['weather'][0];
        for (var weather in d['weather'] as List) {
          codes.add(weather['id']);
        }
        int p = weather['id'];
        if (codePriority.containsKey(p)) {
          p = codePriority[p];
        } else {
          p *= 10; // default mapping
        }
        if (p > priority) {
          mainWeather = weather;
          priority = p;
        }
        humiditySum += d['main']['humidity'];
        var tmax = d['main']['temp_max'];
        if (tmax > temp_max) temp_max = tmax;
        var tmin = d['main']['temp_min'];
        if (tmin < temp_min) temp_min = tmax;
      }
      output.add([
        ts,
        mainWeather['main'],
        codes.join(','),
        mainWeather['description'],
        buildIconUrl(mainWeather['icon']),
        temp_max,
        temp_min,
        humiditySum / group.length,
      ]);
    }
  }
}
