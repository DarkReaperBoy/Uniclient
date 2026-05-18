class CountryInfo {
  final String name;
  final String iso;
  final String dialCode;
  const CountryInfo(this.name, this.iso, this.dialCode);
  String get flag => String.fromCharCodes(
        iso.codeUnits.map((c) => 0x1F1E6 - 0x41 + c),
      );
}

CountryInfo? countryByDialCode(String code) {
  final clean = code.replaceAll(RegExp(r'\D'), '');
  if (clean.isEmpty) return null;
  for (var len = clean.length; len >= 1; len--) {
    final prefix = clean.substring(0, len);
    final match = countries.where((c) => c.dialCode == prefix).firstOrNull;
    if (match != null) return match;
  }
  return null;
}

CountryInfo? countryFromPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  return countryByDialCode(digits);
}

const _phoneGroups = <String, List<int>>{
  '1': [3, 3, 4],
  '7': [3, 3, 2, 2],
  '44': [4, 3, 3],
  '49': [3, 3, 4],
  '33': [1, 2, 2, 2, 2],
  '39': [3, 3, 4],
  '86': [3, 4, 4],
  '81': [2, 4, 4],
  '82': [2, 4, 4],
  '91': [5, 5],
  '55': [2, 5, 4],
  '34': [3, 3, 3],
  '61': [3, 3, 3],
  '90': [3, 3, 2, 2],
  '62': [3, 4, 4],
  '966': [2, 3, 4],
  '971': [2, 3, 4],
  '98': [3, 3, 4],
  '380': [2, 3, 2, 2],
  '48': [3, 3, 3],
  '31': [1, 3, 2, 2],
  '46': [2, 3, 2, 2],
  '47': [3, 2, 3],
  '358': [2, 3, 2, 2],
  '45': [2, 2, 2, 2],
  '32': [3, 2, 2, 2],
  '41': [2, 3, 2, 2],
  '43': [3, 3, 4],
  '351': [3, 3, 3],
  '30': [3, 3, 4],
  '20': [3, 3, 4],
  '27': [2, 3, 4],
  '234': [3, 3, 4],
  '254': [3, 3, 3],
  '52': [2, 4, 4],
  '57': [3, 3, 4],
  '56': [1, 4, 4],
  '54': [2, 4, 4],
};

String formatPhoneDigits(String digits, String dialCode) {
  final groups = _phoneGroups[dialCode];
  if (groups == null || digits.isEmpty) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
  final buf = StringBuffer();
  var pos = 0;
  for (var g = 0; g < groups.length && pos < digits.length; g++) {
    if (g > 0) buf.write(' ');
    final end = (pos + groups[g]).clamp(0, digits.length);
    buf.write(digits.substring(pos, end));
    pos = end;
  }
  if (pos < digits.length) {
    buf.write(' ');
    buf.write(digits.substring(pos));
  }
  return buf.toString();
}

final _countryByIso = <String, String>{
  for (final c in countries) c.iso: c.name,
};

String countryNameByIso(String iso2) {
  return _countryByIso[iso2.toUpperCase()] ?? iso2;
}

const countries = <CountryInfo>[
  CountryInfo('Afghanistan', 'AF', '93'),
  CountryInfo('Albania', 'AL', '355'),
  CountryInfo('Algeria', 'DZ', '213'),
  CountryInfo('Andorra', 'AD', '376'),
  CountryInfo('Angola', 'AO', '244'),
  CountryInfo('Antigua and Barbuda', 'AG', '1268'),
  CountryInfo('Argentina', 'AR', '54'),
  CountryInfo('Armenia', 'AM', '374'),
  CountryInfo('Australia', 'AU', '61'),
  CountryInfo('Austria', 'AT', '43'),
  CountryInfo('Azerbaijan', 'AZ', '994'),
  CountryInfo('Bahamas', 'BS', '1242'),
  CountryInfo('Bahrain', 'BH', '973'),
  CountryInfo('Bangladesh', 'BD', '880'),
  CountryInfo('Barbados', 'BB', '1246'),
  CountryInfo('Belarus', 'BY', '375'),
  CountryInfo('Belgium', 'BE', '32'),
  CountryInfo('Belize', 'BZ', '501'),
  CountryInfo('Benin', 'BJ', '229'),
  CountryInfo('Bhutan', 'BT', '975'),
  CountryInfo('Bolivia', 'BO', '591'),
  CountryInfo('Bosnia and Herzegovina', 'BA', '387'),
  CountryInfo('Botswana', 'BW', '267'),
  CountryInfo('Brazil', 'BR', '55'),
  CountryInfo('Brunei', 'BN', '673'),
  CountryInfo('Bulgaria', 'BG', '359'),
  CountryInfo('Burkina Faso', 'BF', '226'),
  CountryInfo('Burundi', 'BI', '257'),
  CountryInfo('Cambodia', 'KH', '855'),
  CountryInfo('Cameroon', 'CM', '237'),
  CountryInfo('Canada', 'CA', '1'),
  CountryInfo('Cape Verde', 'CV', '238'),
  CountryInfo('Central African Republic', 'CF', '236'),
  CountryInfo('Chad', 'TD', '235'),
  CountryInfo('Chile', 'CL', '56'),
  CountryInfo('China', 'CN', '86'),
  CountryInfo('Colombia', 'CO', '57'),
  CountryInfo('Comoros', 'KM', '269'),
  CountryInfo('Congo', 'CG', '242'),
  CountryInfo('Costa Rica', 'CR', '506'),
  CountryInfo('Croatia', 'HR', '385'),
  CountryInfo('Cuba', 'CU', '53'),
  CountryInfo('Cyprus', 'CY', '357'),
  CountryInfo('Czech Republic', 'CZ', '420'),
  CountryInfo('DR Congo', 'CD', '243'),
  CountryInfo('Denmark', 'DK', '45'),
  CountryInfo('Djibouti', 'DJ', '253'),
  CountryInfo('Dominica', 'DM', '1767'),
  CountryInfo('Dominican Republic', 'DO', '1809'),
  CountryInfo('Ecuador', 'EC', '593'),
  CountryInfo('Egypt', 'EG', '20'),
  CountryInfo('El Salvador', 'SV', '503'),
  CountryInfo('Equatorial Guinea', 'GQ', '240'),
  CountryInfo('Eritrea', 'ER', '291'),
  CountryInfo('Estonia', 'EE', '372'),
  CountryInfo('Eswatini', 'SZ', '268'),
  CountryInfo('Ethiopia', 'ET', '251'),
  CountryInfo('Fiji', 'FJ', '679'),
  CountryInfo('Finland', 'FI', '358'),
  CountryInfo('France', 'FR', '33'),
  CountryInfo('Gabon', 'GA', '241'),
  CountryInfo('Gambia', 'GM', '220'),
  CountryInfo('Georgia', 'GE', '995'),
  CountryInfo('Germany', 'DE', '49'),
  CountryInfo('Ghana', 'GH', '233'),
  CountryInfo('Greece', 'GR', '30'),
  CountryInfo('Grenada', 'GD', '1473'),
  CountryInfo('Guatemala', 'GT', '502'),
  CountryInfo('Guinea', 'GN', '224'),
  CountryInfo('Guinea-Bissau', 'GW', '245'),
  CountryInfo('Guyana', 'GY', '592'),
  CountryInfo('Haiti', 'HT', '509'),
  CountryInfo('Honduras', 'HN', '504'),
  CountryInfo('Hong Kong', 'HK', '852'),
  CountryInfo('Hungary', 'HU', '36'),
  CountryInfo('Iceland', 'IS', '354'),
  CountryInfo('India', 'IN', '91'),
  CountryInfo('Indonesia', 'ID', '62'),
  CountryInfo('Iran', 'IR', '98'),
  CountryInfo('Iraq', 'IQ', '964'),
  CountryInfo('Ireland', 'IE', '353'),
  CountryInfo('Israel', 'IL', '972'),
  CountryInfo('Italy', 'IT', '39'),
  CountryInfo('Ivory Coast', 'CI', '225'),
  CountryInfo('Jamaica', 'JM', '1876'),
  CountryInfo('Japan', 'JP', '81'),
  CountryInfo('Jordan', 'JO', '962'),
  CountryInfo('Kazakhstan', 'KZ', '77'),
  CountryInfo('Kenya', 'KE', '254'),
  CountryInfo('Kiribati', 'KI', '686'),
  CountryInfo('Kosovo', 'XK', '383'),
  CountryInfo('Kuwait', 'KW', '965'),
  CountryInfo('Kyrgyzstan', 'KG', '996'),
  CountryInfo('Laos', 'LA', '856'),
  CountryInfo('Latvia', 'LV', '371'),
  CountryInfo('Lebanon', 'LB', '961'),
  CountryInfo('Lesotho', 'LS', '266'),
  CountryInfo('Liberia', 'LR', '231'),
  CountryInfo('Libya', 'LY', '218'),
  CountryInfo('Liechtenstein', 'LI', '423'),
  CountryInfo('Lithuania', 'LT', '370'),
  CountryInfo('Luxembourg', 'LU', '352'),
  CountryInfo('Macao', 'MO', '853'),
  CountryInfo('Madagascar', 'MG', '261'),
  CountryInfo('Malawi', 'MW', '265'),
  CountryInfo('Malaysia', 'MY', '60'),
  CountryInfo('Maldives', 'MV', '960'),
  CountryInfo('Mali', 'ML', '223'),
  CountryInfo('Malta', 'MT', '356'),
  CountryInfo('Marshall Islands', 'MH', '692'),
  CountryInfo('Mauritania', 'MR', '222'),
  CountryInfo('Mauritius', 'MU', '230'),
  CountryInfo('Mexico', 'MX', '52'),
  CountryInfo('Micronesia', 'FM', '691'),
  CountryInfo('Moldova', 'MD', '373'),
  CountryInfo('Monaco', 'MC', '377'),
  CountryInfo('Mongolia', 'MN', '976'),
  CountryInfo('Montenegro', 'ME', '382'),
  CountryInfo('Morocco', 'MA', '212'),
  CountryInfo('Mozambique', 'MZ', '258'),
  CountryInfo('Myanmar', 'MM', '95'),
  CountryInfo('Namibia', 'NA', '264'),
  CountryInfo('Nauru', 'NR', '674'),
  CountryInfo('Nepal', 'NP', '977'),
  CountryInfo('Netherlands', 'NL', '31'),
  CountryInfo('New Zealand', 'NZ', '64'),
  CountryInfo('Nicaragua', 'NI', '505'),
  CountryInfo('Niger', 'NE', '227'),
  CountryInfo('Nigeria', 'NG', '234'),
  CountryInfo('North Korea', 'KP', '850'),
  CountryInfo('North Macedonia', 'MK', '389'),
  CountryInfo('Norway', 'NO', '47'),
  CountryInfo('Oman', 'OM', '968'),
  CountryInfo('Pakistan', 'PK', '92'),
  CountryInfo('Palau', 'PW', '680'),
  CountryInfo('Palestine', 'PS', '970'),
  CountryInfo('Panama', 'PA', '507'),
  CountryInfo('Papua New Guinea', 'PG', '675'),
  CountryInfo('Paraguay', 'PY', '595'),
  CountryInfo('Peru', 'PE', '51'),
  CountryInfo('Philippines', 'PH', '63'),
  CountryInfo('Poland', 'PL', '48'),
  CountryInfo('Portugal', 'PT', '351'),
  CountryInfo('Qatar', 'QA', '974'),
  CountryInfo('Romania', 'RO', '40'),
  CountryInfo('Russia', 'RU', '7'),
  CountryInfo('Rwanda', 'RW', '250'),
  CountryInfo('Saint Kitts and Nevis', 'KN', '1869'),
  CountryInfo('Saint Lucia', 'LC', '1758'),
  CountryInfo('Saint Vincent', 'VC', '1784'),
  CountryInfo('Samoa', 'WS', '685'),
  CountryInfo('San Marino', 'SM', '378'),
  CountryInfo('Saudi Arabia', 'SA', '966'),
  CountryInfo('Senegal', 'SN', '221'),
  CountryInfo('Serbia', 'RS', '381'),
  CountryInfo('Seychelles', 'SC', '248'),
  CountryInfo('Sierra Leone', 'SL', '232'),
  CountryInfo('Singapore', 'SG', '65'),
  CountryInfo('Slovakia', 'SK', '421'),
  CountryInfo('Slovenia', 'SI', '386'),
  CountryInfo('Solomon Islands', 'SB', '677'),
  CountryInfo('Somalia', 'SO', '252'),
  CountryInfo('South Africa', 'ZA', '27'),
  CountryInfo('South Korea', 'KR', '82'),
  CountryInfo('South Sudan', 'SS', '211'),
  CountryInfo('Spain', 'ES', '34'),
  CountryInfo('Sri Lanka', 'LK', '94'),
  CountryInfo('Sudan', 'SD', '249'),
  CountryInfo('Suriname', 'SR', '597'),
  CountryInfo('Sweden', 'SE', '46'),
  CountryInfo('Switzerland', 'CH', '41'),
  CountryInfo('Syria', 'SY', '963'),
  CountryInfo('Taiwan', 'TW', '886'),
  CountryInfo('Tajikistan', 'TJ', '992'),
  CountryInfo('Tanzania', 'TZ', '255'),
  CountryInfo('Thailand', 'TH', '66'),
  CountryInfo('Timor-Leste', 'TL', '670'),
  CountryInfo('Togo', 'TG', '228'),
  CountryInfo('Tonga', 'TO', '676'),
  CountryInfo('Trinidad and Tobago', 'TT', '1868'),
  CountryInfo('Tunisia', 'TN', '216'),
  CountryInfo('Turkey', 'TR', '90'),
  CountryInfo('Turkmenistan', 'TM', '993'),
  CountryInfo('Tuvalu', 'TV', '688'),
  CountryInfo('Uganda', 'UG', '256'),
  CountryInfo('Ukraine', 'UA', '380'),
  CountryInfo('United Arab Emirates', 'AE', '971'),
  CountryInfo('United Kingdom', 'GB', '44'),
  CountryInfo('United States', 'US', '1'),
  CountryInfo('Uruguay', 'UY', '598'),
  CountryInfo('Uzbekistan', 'UZ', '998'),
  CountryInfo('Vanuatu', 'VU', '678'),
  CountryInfo('Vatican City', 'VA', '379'),
  CountryInfo('Venezuela', 'VE', '58'),
  CountryInfo('Vietnam', 'VN', '84'),
  CountryInfo('Yemen', 'YE', '967'),
  CountryInfo('Zambia', 'ZM', '260'),
  CountryInfo('Zimbabwe', 'ZW', '263'),
];
