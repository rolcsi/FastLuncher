import CloudKit

enum Votes: String {
    case low
    case medium
    case high
    
    public var weight: Int {
        switch self {
        case .low:
            return 1
        case .medium:
            return 2
        case .high:
            return 3
        }
    }
}

class Restaurant {
    let name: String
    var vote: Votes?
    var recordID: CKRecord.ID
    var votesCount = 0
    
    init(recordID: CKRecord.ID, name: String, vote: Votes? = nil) {
        self.name = name
        self.vote = vote
        self.recordID = recordID
    }
}

protocol CloudKitSynchronizerDelegate: class {
    func receivedResponse(with error: Error?)
}

class CloudKitSynchronizer {

    public weak var delegate: CloudKitSynchronizerDelegate?
    public var restaurants = [Restaurant]()
    
    // MARK: - Public methods
    
    public func fetchRecords(completion: @escaping ([Restaurant], _ canIVote: Bool) -> ()) {
        fetchRestaurantRecords { _ in
            self.fetchVoteRecords { (restaurants, canIVote) in
                completion(restaurants, canIVote)
            }
        }
    }
    
    public func sendVotes() {
        let restaurants = self.restaurants.filter { $0.vote != nil }
        let publicDatabase = CKContainer.default().publicCloudDatabase
        
        var receivedError: Error?
        
        for restaurant in restaurants {
            guard receivedError == nil,  let vote = restaurant.vote else { return }
            
            let reference = CKRecord.Reference(recordID: restaurant.recordID, action: .none)
            let voteRecord = CKRecord(recordType: "Votes")
            voteRecord.setValue(vote.rawValue, forKey: "priority")
            voteRecord.setObject(reference, forKey: "restaurant")
            
            publicDatabase.save(voteRecord) { (record, error) -> Void in
                if let error = error {
                    receivedError = error
                } else if record == nil {
                    receivedError = NSError()
                }
            }
        }
        
        // TODO: Do after save block finished
        delegate?.receivedResponse(with: receivedError)
    }
    
    public func sendRestaurant(name: String) {
        let restaurantRecord = CKRecord(recordType: "Restaurants")
        restaurantRecord.setObject(name as __CKRecordObjCValue, forKey: "name")
        
        let publicDatabase = CKContainer.default().publicCloudDatabase
        publicDatabase.save(restaurantRecord) { (record, error) -> Void in
            var receivedError: Error?
            
            if let error = error {
                receivedError = error
            } else if record == nil {
                receivedError = NSError()
            }
            
            self.delegate?.receivedResponse(with: receivedError)
        }
    }
    
    // MARK: Private methods
    
    private func sortRestaurants() {
        restaurants.sort { (lhs, rhs) -> Bool in
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    private func fetchRestaurantRecords(completion: @escaping ([Restaurant]) -> ()) {
        restaurants = []
        
        let defaultContainer = CKContainer.default()
        let publicDatabase = defaultContainer.publicCloudDatabase
        let query = CKQuery(recordType: "Restaurants", predicate: NSPredicate(value: true))
        
        publicDatabase.perform(query, inZoneWith: nil) { (records, error) in
            records?.forEach({ (record) in
                let name = record.value(forKey: "name") as? String
                self.restaurants.append(Restaurant(recordID: record.recordID, name: name ?? ""))
            })
            
            self.sortRestaurants()
            completion(self.restaurants)
        }
    }
    
    private func fetchVoteRecords(completion: @escaping ([Restaurant], _ canIVote: Bool) -> ()) {
        for restaurant in restaurants {
            restaurant.votesCount = 0
        }
        
        let defaultContainer = CKContainer.default()
        let publicDatabase = defaultContainer.publicCloudDatabase
        
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        let result = formatter.string(from: date)
        let today = formatter.date(from: result)!
        
        var canIVote = true
        
        let query = CKQuery(recordType: "Votes", predicate: NSPredicate(format: "creationDate > %@", today as NSDate))
        publicDatabase.perform(query, inZoneWith: nil) { (records, error) in
            records?.forEach({ (record) in
                
                // Check if I did vote today
                if record.creatorUserRecordID?.recordName == "__defaultOwner__" {
                    canIVote = false
                }
                
                // TODO: Check if other users have exactly 3 votes
                // TODO: Check if votes aren't modified
                
                guard let priority = record.value(forKey: "priority") as? String, let vote = Votes.init(rawValue: priority) else { return }
                
                if let recordRestaurant = record.value(forKey: "restaurant") as? CKRecord.Reference {
                    let restaurant = self.restaurants.first(where: { $0.recordID == recordRestaurant.recordID })
                    restaurant?.votesCount += vote.weight
                }
            })
            
            completion(self.restaurants, canIVote)
        }
    }
}
