//
//  UserProfile.swift
//  StudyAI
//
//  Created by Claude Code on 9/16/25.
//

import Foundation

// MARK: - Enhanced User Profile Model

struct UserProfile: Codable {
    let id: String
    let email: String
    let name: String
    let profileImageUrl: String?
    let authProvider: String
    
    // Enhanced profile fields
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let gradeLevel: String?
    let dateOfBirth: Date?
    let kidsAges: [Int]
    let gender: String?
    let city: String?
    let stateProvince: String?
    let country: String?
    let favoriteSubjects: [String]
    let learningStyle: String?
    let timezone: String?
    let languagePreference: String?
    let profileCompletionPercentage: Int
    let lastUpdated: Date?
    
    // Computed properties for display
    var fullName: String {
        if let firstName = firstName, let lastName = lastName {
            return "\(firstName) \(lastName)"
        } else if let displayName = displayName {
            return displayName
        } else {
            return name
        }
    }
    
    var displayLocation: String? {
        let components = [city, stateProvince, country].compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
    
    var isProfileComplete: Bool {
        return profileCompletionPercentage >= 80
    }
    
    var kidsAgesDisplay: String {
        if kidsAges.isEmpty {
            return "Not specified"
        } else if kidsAges.count == 1 {
            return "\(kidsAges[0]) years old"
        } else {
            let sorted = kidsAges.sorted()
            return sorted.map { "\($0)" }.joined(separator: ", ") + " years old"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, email, name
        case profileImageUrl = "profileImageURL"
        case authProvider, firstName, lastName, displayName, gradeLevel
        case dateOfBirth, kidsAges, gender, city
        case stateProvince = "stateProvince"
        case country, favoriteSubjects, learningStyle, timezone, languagePreference
        case profileCompletionPercentage, lastUpdated
    }
    
    // Custom date handling for JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        name = try container.decode(String.self, forKey: .name)
        profileImageUrl = try container.decodeIfPresent(String.self, forKey: .profileImageUrl)
        authProvider = try container.decode(String.self, forKey: .authProvider)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        gradeLevel = try container.decodeIfPresent(String.self, forKey: .gradeLevel)
        
        // Handle date decoding
        if let dateString = try container.decodeIfPresent(String.self, forKey: .dateOfBirth) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dateOfBirth = formatter.date(from: dateString)
        } else {
            dateOfBirth = nil
        }
        
        kidsAges = try container.decodeIfPresent([Int].self, forKey: .kidsAges) ?? []
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        stateProvince = try container.decodeIfPresent(String.self, forKey: .stateProvince)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        favoriteSubjects = try container.decodeIfPresent([String].self, forKey: .favoriteSubjects) ?? []
        learningStyle = try container.decodeIfPresent(String.self, forKey: .learningStyle)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        languagePreference = try container.decodeIfPresent(String.self, forKey: .languagePreference)
        profileCompletionPercentage = try container.decodeIfPresent(Int.self, forKey: .profileCompletionPercentage) ?? 0
        
        // Handle lastUpdated date
        if let lastUpdatedString = try container.decodeIfPresent(String.self, forKey: .lastUpdated) {
            let formatter = ISO8601DateFormatter()
            lastUpdated = formatter.date(from: lastUpdatedString)
        } else {
            lastUpdated = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(profileImageUrl, forKey: .profileImageUrl)
        try container.encode(authProvider, forKey: .authProvider)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(gradeLevel, forKey: .gradeLevel)
        
        // Handle date encoding
        if let dateOfBirth = dateOfBirth {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            try container.encode(formatter.string(from: dateOfBirth), forKey: .dateOfBirth)
        }
        
        try container.encode(kidsAges, forKey: .kidsAges)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(stateProvince, forKey: .stateProvince)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encode(favoriteSubjects, forKey: .favoriteSubjects)
        try container.encodeIfPresent(learningStyle, forKey: .learningStyle)
        try container.encodeIfPresent(timezone, forKey: .timezone)
        try container.encodeIfPresent(languagePreference, forKey: .languagePreference)
        try container.encode(profileCompletionPercentage, forKey: .profileCompletionPercentage)
        
        // Handle lastUpdated encoding
        if let lastUpdated = lastUpdated {
            let formatter = ISO8601DateFormatter()
            try container.encode(formatter.string(from: lastUpdated), forKey: .lastUpdated)
        }
    }
}

// MARK: - Profile Update Request Model

struct ProfileUpdateRequest: Codable {
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let gradeLevel: String?
    let dateOfBirth: String? // Send as string in YYYY-MM-DD format
    let kidsAges: [Int]
    let gender: String?
    let city: String?
    let stateProvince: String?
    let country: String?
    let favoriteSubjects: [String]
    let learningStyle: String?
    let timezone: String?
    let languagePreference: String?
    
    init(from profile: UserProfile) {
        self.firstName = profile.firstName
        self.lastName = profile.lastName
        self.displayName = profile.displayName
        self.gradeLevel = profile.gradeLevel
        
        // Convert date to string
        if let dateOfBirth = profile.dateOfBirth {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            self.dateOfBirth = formatter.string(from: dateOfBirth)
        } else {
            self.dateOfBirth = nil
        }
        
        self.kidsAges = profile.kidsAges
        self.gender = profile.gender
        self.city = profile.city
        self.stateProvince = profile.stateProvince
        self.country = profile.country
        self.favoriteSubjects = profile.favoriteSubjects
        self.learningStyle = profile.learningStyle
        self.timezone = profile.timezone
        self.languagePreference = profile.languagePreference
    }
}

// MARK: - Profile Response Models

struct ProfileResponse: Codable {
    let success: Bool
    let profile: UserProfile
    let message: String?
}

struct ProfileCompletionResponse: Codable {
    let success: Bool
    let completion: ProfileCompletion
}

struct ProfileCompletion: Codable {
    let percentage: Int
    let isComplete: Bool
    let onboardingCompleted: Bool
}

// MARK: - Constants and Enums

enum GradeLevel: String, CaseIterable {
    case preK = "Pre-K"
    case kindergarten = "Kindergarten"
    case grade1 = "1st Grade"
    case grade2 = "2nd Grade"
    case grade3 = "3rd Grade"
    case grade4 = "4th Grade"
    case grade5 = "5th Grade"
    case grade6 = "6th Grade"
    case grade7 = "7th Grade"
    case grade8 = "8th Grade"
    case grade9 = "9th Grade"
    case grade10 = "10th Grade"
    case grade11 = "11th Grade"
    case grade12 = "12th Grade"
    case college = "College"
    case adult = "Adult Learner"
    
    var displayName: String {
        return self.rawValue
    }
}

enum LearningStyle: String, CaseIterable {
    case visual = "visual"
    case auditory = "auditory"
    case kinesthetic = "kinesthetic"
    case reading = "reading"
    case adaptive = "adaptive"
    
    var displayName: String {
        switch self {
        case .visual: return "Visual"
        case .auditory: return "Auditory"
        case .kinesthetic: return "Kinesthetic/Hands-on"
        case .reading: return "Reading/Writing"
        case .adaptive: return "Adaptive (Let AI decide)"
        }
    }
    
    var description: String {
        switch self {
        case .visual: return "Learn best with images, diagrams, and visual aids"
        case .auditory: return "Learn best by listening and discussing"
        case .kinesthetic: return "Learn best through hands-on activities"
        case .reading: return "Learn best through reading and writing"
        case .adaptive: return "AI adapts teaching style based on your responses"
        }
    }
}

enum Subject: String, CaseIterable {
    case math = "Math"
    case science = "Science"
    case english = "English"
    case history = "History"
    case geography = "Geography"
    case physics = "Physics"
    case chemistry = "Chemistry"
    case biology = "Biology"
    case computerScience = "Computer Science"
    case foreignLanguage = "Foreign Language"
    case art = "Art"
    case music = "Music"
    case physicalEducation = "Physical Education"
    
    var displayName: String {
        return self.rawValue
    }
}

// MARK: - UserProfile Extensions

extension UserProfile {
    /// Create UserProfile from dictionary
    static func fromDictionary(_ dict: [String: Any]) throws -> UserProfile {
        guard let id = dict["id"] as? String ?? dict["userId"] as? String ?? dict["user_id"] as? String,
              let email = dict["email"] as? String else {
            throw ProfileError.validationError("Missing required profile fields: id and email")
        }
        
        // Handle name field - construct from firstName/lastName if name is not provided
        let name: String
        if let providedName = dict["name"] as? String {
            name = providedName
        } else if let firstName = dict["firstName"] as? String, 
                  let lastName = dict["lastName"] as? String {
            name = "\(firstName) \(lastName)"
        } else if let firstName = dict["firstName"] as? String {
            name = firstName
        } else if let lastName = dict["lastName"] as? String {
            name = lastName
        } else {
            // If no name components are available, use email prefix as fallback
            name = String(email.split(separator: "@").first ?? "User")
        }
        
        // Parse date of birth
        var dateOfBirth: Date?
        if let dobString = dict["dateOfBirth"] as? String ?? dict["date_of_birth"] as? String {
            // Try ISO8601 format first
            let iso8601Formatter = ISO8601DateFormatter()
            dateOfBirth = iso8601Formatter.date(from: dobString)
            
            // If that fails, try date-only format (YYYY-MM-DD)
            if dateOfBirth == nil {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateOfBirth = dateFormatter.date(from: dobString)
            }
        }
        
        // Parse last updated
        var lastUpdated: Date?
        if let lastUpdatedString = dict["lastUpdated"] as? String ?? dict["last_updated"] as? String {
            let formatter = ISO8601DateFormatter()
            lastUpdated = formatter.date(from: lastUpdatedString)
        }
        
        // Parse kids ages array
        var kidsAges: [Int] = []
        if let kidsAgesArray = dict["kidsAges"] as? [Any] ?? dict["kids_ages"] as? [Any] {
            kidsAges = kidsAgesArray.compactMap { $0 as? Int }
        }
        
        // Parse favorite subjects array
        var favoriteSubjects: [String] = []
        if let subjectsArray = dict["favoriteSubjects"] as? [String] ?? dict["favorite_subjects"] as? [String] {
            favoriteSubjects = subjectsArray
        }
        
        return UserProfile(
            id: id,
            email: email,
            name: name,
            profileImageUrl: dict["profileImageUrl"] as? String ?? dict["profile_image_url"] as? String,
            authProvider: dict["authProvider"] as? String ?? dict["auth_provider"] as? String ?? "email",
            firstName: dict["firstName"] as? String ?? dict["first_name"] as? String,
            lastName: dict["lastName"] as? String ?? dict["last_name"] as? String,
            displayName: dict["displayName"] as? String ?? dict["display_name"] as? String,
            gradeLevel: dict["gradeLevel"] as? String ?? dict["grade_level"] as? String,
            dateOfBirth: dateOfBirth,
            kidsAges: kidsAges,
            gender: dict["gender"] as? String,
            city: dict["city"] as? String,
            stateProvince: dict["stateProvince"] as? String ?? dict["state_province"] as? String,
            country: dict["country"] as? String,
            favoriteSubjects: favoriteSubjects,
            learningStyle: dict["learningStyle"] as? String ?? dict["learning_style"] as? String,
            timezone: dict["timezone"] as? String ?? "UTC",
            languagePreference: dict["languagePreference"] as? String ?? dict["language_preference"] as? String ?? "en",
            profileCompletionPercentage: dict["profileCompletionPercentage"] as? Int ?? dict["profile_completion_percentage"] as? Int ?? 0,
            lastUpdated: lastUpdated
        )
    }
    
    /// Convert UserProfile to dictionary
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "email": email,
            "name": name,
            "authProvider": authProvider,
            "kidsAges": kidsAges,
            "favoriteSubjects": favoriteSubjects,
            "timezone": timezone as String?,
            "languagePreference": languagePreference as String?,
            "profileCompletionPercentage": profileCompletionPercentage
        ]
        
        // Add optional fields only if they have values
        if let profileImageUrl = profileImageUrl {
            dict["profileImageUrl"] = profileImageUrl
        }
        if let firstName = firstName {
            dict["firstName"] = firstName
        }
        if let lastName = lastName {
            dict["lastName"] = lastName
        }
        if let displayName = displayName {
            dict["displayName"] = displayName
        }
        if let gradeLevel = gradeLevel {
            dict["gradeLevel"] = gradeLevel
        }
        if let dateOfBirth = dateOfBirth {
            // Backend expects date format "YYYY-MM-DD", not full ISO8601 datetime
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dict["dateOfBirth"] = formatter.string(from: dateOfBirth)
        }
        if let gender = gender {
            dict["gender"] = gender
        }
        if let city = city {
            dict["city"] = city
        }
        if let stateProvince = stateProvince {
            dict["stateProvince"] = stateProvince
        }
        if let country = country {
            dict["country"] = country
        }
        if let learningStyle = learningStyle {
            dict["learningStyle"] = learningStyle
        }
        if let lastUpdated = lastUpdated {
            let formatter = ISO8601DateFormatter()
            dict["lastUpdated"] = formatter.string(from: lastUpdated)
        }
        
        return dict
    }
    
    /// Standard initializer that takes individual parameters
    init(
        id: String,
        email: String,
        name: String,
        profileImageUrl: String? = nil,
        authProvider: String,
        firstName: String? = nil,
        lastName: String? = nil,
        displayName: String? = nil,
        gradeLevel: String? = nil,
        dateOfBirth: Date? = nil,
        kidsAges: [Int] = [],
        gender: String? = nil,
        city: String? = nil,
        stateProvince: String? = nil,
        country: String? = nil,
        favoriteSubjects: [String] = [],
        learningStyle: String? = nil,
        timezone: String = "UTC",
        languagePreference: String = "en",
        profileCompletionPercentage: Int = 0,
        lastUpdated: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.profileImageUrl = profileImageUrl
        self.authProvider = authProvider
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
        self.gradeLevel = gradeLevel
        self.dateOfBirth = dateOfBirth
        self.kidsAges = kidsAges
        self.gender = gender
        self.city = city
        self.stateProvince = stateProvince
        self.country = country
        self.favoriteSubjects = favoriteSubjects
        self.learningStyle = learningStyle
        self.timezone = timezone
        self.languagePreference = languagePreference
        self.profileCompletionPercentage = profileCompletionPercentage
        self.lastUpdated = lastUpdated
    }
}

// MARK: - ProfileCompletion Extensions

extension ProfileCompletion {
    /// Create ProfileCompletion from dictionary
    static func fromDictionary(_ dict: [String: Any]) -> ProfileCompletion {
        let percentage = dict["percentage"] as? Int ?? dict["completionPercentage"] as? Int ?? dict["completion_percentage"] as? Int ?? 0
        let isComplete = dict["isComplete"] as? Bool ?? dict["is_complete"] as? Bool ?? false
        let onboardingCompleted = dict["onboardingCompleted"] as? Bool ?? dict["onboarding_completed"] as? Bool ?? false
        
        // Create JSON data and decode it to construct ProfileCompletion
        let jsonDict: [String: Any] = [
            "percentage": percentage,
            "isComplete": isComplete,
            "onboardingCompleted": onboardingCompleted
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
            let decoder = JSONDecoder()
            return try decoder.decode(ProfileCompletion.self, from: jsonData)
        } catch {
            // Fallback: return a default ProfileCompletion
            print("⚠️ Failed to decode ProfileCompletion: \(error)")
            let fallbackDict: [String: Any] = [
                "percentage": 0,
                "isComplete": false,
                "onboardingCompleted": false
            ]
            let fallbackData = try! JSONSerialization.data(withJSONObject: fallbackDict)
            return try! JSONDecoder().decode(ProfileCompletion.self, from: fallbackData)
        }
    }
}