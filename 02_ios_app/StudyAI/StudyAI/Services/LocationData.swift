//
//  LocationData.swift
//  StudyAI
//

import Foundation

// MARK: - LocationData
// Provides country and state/province lists without any external database.
// Country names come from iOS Locale (fully localized, zero bundle cost).
// State/province lists are hardcoded for the 25 most common countries.

struct LocationData {

    // MARK: - Countries

    /// Returns all countries sorted by localized display name.
    /// Pass a custom locale for testing; defaults to the device locale.
    static func allCountries(locale: Locale = .current) -> [(code: String, name: String)] {
        Locale.Region.isoRegions
            .compactMap { region -> (String, String)? in
                let code = region.identifier
                guard let name = locale.localizedString(forRegionCode: code),
                      !name.isEmpty else { return nil }
                return (code, name)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Returns the English display name for a country code (for backend storage).
    static func englishName(for code: String) -> String? {
        Locale(identifier: "en_US").localizedString(forRegionCode: code)
    }

    /// Finds a country code for a stored country string (2-letter code or English name).
    static func countryCode(for stored: String) -> String? {
        let upper = stored.uppercased()
        // Direct ISO code match (e.g. "US", "CN")
        if stored.count == 2,
           Locale.Region.isoRegions.contains(where: { $0.identifier == upper }) {
            return upper
        }
        // English name match
        let enLocale = Locale(identifier: "en_US")
        return Locale.Region.isoRegions.first {
            enLocale.localizedString(forRegionCode: $0.identifier)?
                .caseInsensitiveCompare(stored) == .orderedSame
        }?.identifier
    }

    // MARK: - States / Provinces

    /// State/province lists for major countries.
    /// Keys are ISO 3166-1 alpha-2 country codes.
    static let statesForCountry: [String: [String]] = [
        "US": [
            "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado",
            "Connecticut", "Delaware", "Florida", "Georgia", "Hawaii", "Idaho",
            "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana",
            "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota",
            "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada",
            "New Hampshire", "New Jersey", "New Mexico", "New York",
            "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon",
            "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota",
            "Tennessee", "Texas", "Utah", "Vermont", "Virginia", "Washington",
            "West Virginia", "Wisconsin", "Wyoming", "District of Columbia"
        ],
        "CA": [
            "Alberta", "British Columbia", "Manitoba", "New Brunswick",
            "Newfoundland and Labrador", "Northwest Territories", "Nova Scotia",
            "Nunavut", "Ontario", "Prince Edward Island", "Quebec",
            "Saskatchewan", "Yukon"
        ],
        "AU": [
            "Australian Capital Territory", "New South Wales", "Northern Territory",
            "Queensland", "South Australia", "Tasmania", "Victoria", "Western Australia"
        ],
        "CN": [
            "Anhui", "Beijing", "Chongqing", "Fujian", "Gansu", "Guangdong",
            "Guangxi", "Guizhou", "Hainan", "Hebei", "Heilongjiang", "Henan",
            "Hong Kong", "Hubei", "Hunan", "Inner Mongolia", "Jiangsu",
            "Jiangxi", "Jilin", "Liaoning", "Macau", "Ningxia", "Qinghai",
            "Shaanxi", "Shandong", "Shanghai", "Shanxi", "Sichuan", "Tianjin",
            "Tibet", "Xinjiang", "Yunnan", "Zhejiang"
        ],
        "GB": ["England", "Northern Ireland", "Scotland", "Wales"],
        "DE": [
            "Baden-Württemberg", "Bavaria", "Berlin", "Brandenburg", "Bremen",
            "Hamburg", "Hesse", "Lower Saxony", "Mecklenburg-Vorpommern",
            "North Rhine-Westphalia", "Rhineland-Palatinate", "Saarland",
            "Saxony", "Saxony-Anhalt", "Schleswig-Holstein", "Thuringia"
        ],
        "IN": [
            "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar",
            "Chhattisgarh", "Delhi", "Goa", "Gujarat", "Haryana",
            "Himachal Pradesh", "Jammu and Kashmir", "Jharkhand", "Karnataka",
            "Kerala", "Ladakh", "Madhya Pradesh", "Maharashtra", "Manipur",
            "Meghalaya", "Mizoram", "Nagaland", "Odisha", "Punjab",
            "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
            "Uttar Pradesh", "Uttarakhand", "West Bengal"
        ],
        "MX": [
            "Aguascalientes", "Baja California", "Baja California Sur",
            "Campeche", "Chiapas", "Chihuahua", "Coahuila", "Colima",
            "Durango", "Guanajuato", "Guerrero", "Hidalgo", "Jalisco",
            "Mexico City", "México", "Michoacán", "Morelos", "Nayarit",
            "Nuevo León", "Oaxaca", "Puebla", "Querétaro", "Quintana Roo",
            "San Luis Potosí", "Sinaloa", "Sonora", "Tabasco", "Tamaulipas",
            "Tlaxcala", "Veracruz", "Yucatán", "Zacatecas"
        ],
        "BR": [
            "Acre", "Alagoas", "Amapá", "Amazonas", "Bahia", "Ceará",
            "Distrito Federal", "Espírito Santo", "Goiás", "Maranhão",
            "Mato Grosso", "Mato Grosso do Sul", "Minas Gerais", "Pará",
            "Paraíba", "Paraná", "Pernambuco", "Piauí", "Rio de Janeiro",
            "Rio Grande do Norte", "Rio Grande do Sul", "Rondônia", "Roraima",
            "Santa Catarina", "São Paulo", "Sergipe", "Tocantins"
        ],
        "JP": [
            "Aichi", "Akita", "Aomori", "Chiba", "Ehime", "Fukui", "Fukuoka",
            "Fukushima", "Gifu", "Gunma", "Hiroshima", "Hokkaido", "Hyogo",
            "Ibaraki", "Ishikawa", "Iwate", "Kagawa", "Kagoshima", "Kanagawa",
            "Kochi", "Kumamoto", "Kyoto", "Mie", "Miyagi", "Miyazaki",
            "Nagano", "Nagasaki", "Nara", "Niigata", "Oita", "Okayama",
            "Okinawa", "Osaka", "Saga", "Saitama", "Shiga", "Shimane",
            "Shizuoka", "Tochigi", "Tokushima", "Tokyo", "Tottori", "Toyama",
            "Wakayama", "Yamagata", "Yamaguchi", "Yamanashi"
        ],
        "KR": [
            "Busan", "Chungbuk", "Chungnam", "Daegu", "Daejeon", "Gangwon",
            "Gwangju", "Gyeongbuk", "Gyeonggi", "Gyeongnam", "Incheon",
            "Jeju", "Jeonbuk", "Jeonnam", "Sejong", "Seoul", "Ulsan"
        ],
        "FR": [
            "Auvergne-Rhône-Alpes", "Bourgogne-Franche-Comté", "Bretagne",
            "Centre-Val de Loire", "Corse", "Grand Est", "Hauts-de-France",
            "Île-de-France", "Normandie", "Nouvelle-Aquitaine", "Occitanie",
            "Pays de la Loire", "Provence-Alpes-Côte d'Azur"
        ],
        "ES": [
            "Andalucía", "Aragón", "Asturias", "Canarias", "Cantabria",
            "Castilla-La Mancha", "Castilla y León", "Cataluña",
            "Comunidad de Madrid", "Comunidad Valenciana", "Extremadura",
            "Galicia", "Illes Balears", "La Rioja", "Murcia", "Navarra",
            "País Vasco"
        ],
        "IT": [
            "Abruzzo", "Basilicata", "Calabria", "Campania", "Emilia-Romagna",
            "Friuli-Venezia Giulia", "Lazio", "Liguria", "Lombardia", "Marche",
            "Molise", "Piemonte", "Puglia", "Sardegna", "Sicilia", "Toscana",
            "Trentino-Alto Adige", "Umbria", "Valle d'Aosta", "Veneto"
        ],
        "NZ": [
            "Auckland", "Bay of Plenty", "Canterbury", "Gisborne",
            "Hawke's Bay", "Manawatū-Whanganui", "Marlborough", "Nelson",
            "Northland", "Otago", "Southland", "Taranaki", "Tasman",
            "Waikato", "Wellington", "West Coast"
        ],
        "ZA": [
            "Eastern Cape", "Free State", "Gauteng", "KwaZulu-Natal",
            "Limpopo", "Mpumalanga", "North West", "Northern Cape",
            "Western Cape"
        ],
        "AR": [
            "Buenos Aires", "Catamarca", "Chaco", "Chubut",
            "Ciudad Autónoma de Buenos Aires", "Córdoba", "Corrientes",
            "Entre Ríos", "Formosa", "Jujuy", "La Pampa", "La Rioja",
            "Mendoza", "Misiones", "Neuquén", "Río Negro", "Salta",
            "San Juan", "San Luis", "Santa Cruz", "Santa Fe",
            "Santiago del Estero", "Tierra del Fuego", "Tucumán"
        ],
        "CO": [
            "Antioquia", "Atlántico", "Bogotá D.C.", "Bolívar", "Boyacá",
            "Caldas", "Caquetá", "Cauca", "Cesar", "Chocó", "Córdoba",
            "Cundinamarca", "Huila", "La Guajira", "Magdalena", "Meta",
            "Nariño", "Norte de Santander", "Quindío", "Risaralda",
            "San Andrés y Providencia", "Santander", "Sucre", "Tolima",
            "Valle del Cauca"
        ],
        "CL": [
            "Antofagasta", "Araucanía", "Arica y Parinacota", "Atacama",
            "Aysén", "Biobío", "Coquimbo", "Los Lagos", "Los Ríos",
            "Magallanes", "Maule", "Metropolitana de Santiago", "Ñuble",
            "O'Higgins", "Tarapacá", "Valparaíso"
        ],
        "RU": [
            "Altai Republic", "Amur", "Arkhangelsk", "Astrakhan", "Belgorod",
            "Bryansk", "Buryatia", "Chechnya", "Chelyabinsk", "Chukotka",
            "Dagestan", "Irkutsk", "Ivanovo", "Kabardino-Balkaria",
            "Kaliningrad", "Kaluga", "Kamchatka", "Karachay-Cherkessia",
            "Karelia", "Kemerovo", "Khabarovsk", "Khakassia", "Kirov",
            "Komi", "Kostroma", "Krasnodar", "Krasnoyarsk", "Kurgan",
            "Kursk", "Leningrad", "Lipetsk", "Magadan", "Mari El",
            "Mordovia", "Moscow", "Moscow Oblast", "Murmansk",
            "Nizhny Novgorod", "Novgorod", "Novosibirsk", "Omsk",
            "Orel", "Orenburg", "Penza", "Perm", "Primorsky", "Pskov",
            "Rostov", "Ryazan", "Saint Petersburg", "Sakha", "Sakhalin",
            "Samara", "Saratov", "Smolensk", "Stavropol", "Sverdlovsk",
            "Tambov", "Tatarstan", "Tomsk", "Tula", "Tuva", "Tver",
            "Tyumen", "Udmurtia", "Ulyanovsk", "Vladimir", "Volgograd",
            "Vologda", "Voronezh", "Yaroslavl", "Zabaykalsky"
        ],
        "TR": [
            "Adana", "Adıyaman", "Ankara", "Antalya", "Artvin", "Aydın",
            "Balıkesir", "Bursa", "Denizli", "Diyarbakır", "Edirne",
            "Erzurum", "Eskişehir", "Gaziantep", "Hatay", "İstanbul",
            "İzmir", "Kahramanmaraş", "Kayseri", "Konya", "Malatya",
            "Manisa", "Mersin", "Muğla", "Ordu", "Sakarya", "Samsun",
            "Sivas", "Şanlıurfa", "Tekirdağ", "Trabzon", "Van", "Zonguldak"
        ],
        "MY": [
            "Johor", "Kedah", "Kelantan", "Kuala Lumpur", "Labuan",
            "Melaka", "Negeri Sembilan", "Pahang", "Perak", "Perlis",
            "Pulau Pinang", "Putrajaya", "Sabah", "Sarawak", "Selangor",
            "Terengganu"
        ],
        "ID": [
            "Aceh", "Bali", "Bangka Belitung", "Banten", "Bengkulu",
            "DKI Jakarta", "Gorontalo", "Jambi", "Jawa Barat", "Jawa Tengah",
            "Jawa Timur", "Kalimantan Barat", "Kalimantan Selatan",
            "Kalimantan Tengah", "Kalimantan Timur", "Kalimantan Utara",
            "Kepulauan Riau", "Lampung", "Maluku", "Maluku Utara",
            "Nusa Tenggara Barat", "Nusa Tenggara Timur", "Papua",
            "Papua Barat", "Riau", "Sulawesi Barat", "Sulawesi Selatan",
            "Sulawesi Tengah", "Sulawesi Tenggara", "Sulawesi Utara",
            "Sumatera Barat", "Sumatera Selatan", "Sumatera Utara",
            "Yogyakarta"
        ],
        "PK": [
            "Azad Kashmir", "Balochistan", "Gilgit-Baltistan",
            "Islamabad Capital Territory", "Khyber Pakhtunkhwa", "Punjab",
            "Sindh"
        ],
        "SG": [
            "Central Region", "East Region", "North Region",
            "North-East Region", "West Region"
        ],
        "PH": [
            "Abra", "Agusan del Norte", "Agusan del Sur", "Aklan", "Albay",
            "Antique", "Apayao", "Aurora", "Basilan", "Bataan", "Batanes",
            "Batangas", "Benguet", "Bohol", "Bukidnon", "Bulacan",
            "Cagayan", "Camarines Norte", "Camarines Sur", "Camiguin",
            "Capiz", "Catanduanes", "Cavite", "Cebu", "Cotabato",
            "Davao de Oro", "Davao del Norte", "Davao del Sur",
            "Davao Oriental", "Dinagat Islands", "Eastern Samar",
            "Guimaras", "Ifugao", "Ilocos Norte", "Ilocos Sur", "Iloilo",
            "Isabela", "Kalinga", "La Union", "Laguna", "Lanao del Norte",
            "Lanao del Sur", "Leyte", "Marinduque", "Masbate", "Metro Manila",
            "Misamis Occidental", "Misamis Oriental", "Mountain Province",
            "Negros Occidental", "Negros Oriental", "Northern Samar",
            "Nueva Ecija", "Nueva Vizcaya", "Occidental Mindoro",
            "Oriental Mindoro", "Palawan", "Pampanga", "Pangasinan",
            "Quezon", "Quirino", "Rizal", "Romblon", "Samar", "Sarangani",
            "Siquijor", "Sorsogon", "South Cotabato", "Southern Leyte",
            "Sultan Kudarat", "Sulu", "Surigao del Norte", "Surigao del Sur",
            "Tarlac", "Tawi-Tawi", "Zambales", "Zamboanga del Norte",
            "Zamboanga del Sur", "Zamboanga Sibugay"
        ],
    ]

    /// Returns true if a state/province list is available for the given country code.
    static func hasStates(for countryCode: String) -> Bool {
        statesForCountry[countryCode] != nil
    }

    /// Returns the sorted state/province list for a country code, or nil if not available.
    static func states(for countryCode: String) -> [String]? {
        statesForCountry[countryCode]
    }
}
