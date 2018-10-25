import UIKit
import CloudKit

class RestaurantsViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var confirmButton: UIButton!
    
    private var synchronizer = CloudKitSynchronizer()
    private var usedVotes: [Votes] = []
    private var unusedVotes = [Votes.low, Votes.medium, Votes.high]
    private let cellIdentifier = "RestaurantCell"
    private var canIvote = true {
        didSet {
            DispatchQueue.main.sync {
                confirmButton.isEnabled = canIvote
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        synchronizer.delegate = self
        synchronizer.fetchRecords { [weak self] (_, canIVote) in
            self?.canIvote = canIVote
            self?.updateTable()
        }
    }

    // MARK: - Outlet actions
    
    @IBAction func addBarButtonPressed(_ sender: Any) {
        let alertController = UIAlertController(title: "Add", message: "Name of a restaurant:", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "Restaurant"
        }
        
        let confirmAction = UIAlertAction(title: "OK", style: .default) { _ in
            if let text = alertController.textFields?.first?.text {
                self.synchronizer.sendRestaurant(name: text)
            }
        }
        alertController.addAction(confirmAction)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    @IBAction func reloadBarButtonPressed(_ sender: Any) {
        synchronizer.fetchRecords { [weak self] (_, canIVote) in
            self?.canIvote = canIVote
            self?.updateTable()
        }
    }
    
    @IBAction func confirmButtonPressed(_ sender: Any) {
        synchronizer.sendVotes()
    }
    
    // MARK: - Private methods
    
    private func updateTable() {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    private func makeVote(for indexPath: IndexPath) -> Restaurant? {
        let restaurant = synchronizer.restaurants[indexPath.row]
        
        if let vote = restaurant.vote {
            if !unusedVotes.isEmpty {
                guard let unusedVote = unusedVotes.first else { return nil }
                restaurant.vote = unusedVote
                if let index = unusedVotes.firstIndex(of: unusedVote) {
                    unusedVotes.remove(at: index)
                }
                unusedVotes.append(vote)
            } else {
                unusedVotes.append(vote)
                restaurant.vote = nil
            }
        } else if !unusedVotes.isEmpty {
            guard let vote = unusedVotes.first else { return nil }
            
            restaurant.vote = vote
            if let index = unusedVotes.firstIndex(of: vote) {
                unusedVotes.remove(at: index)
            }
        }
        
        return restaurant
    }
}

extension RestaurantsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let restaurant = makeVote(for: indexPath),
            let cell = tableView.cellForRow(at: indexPath) as? RestaurantTableViewCell else { return }
        
        cell.yourVoteLabel.text = restaurant.vote?.rawValue
    }
}

extension RestaurantsViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return synchronizer.restaurants.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as? RestaurantTableViewCell else { fatalError() }
        
        let restaurant = synchronizer.restaurants[indexPath.row]
        cell.nameLabel.text = restaurant.name
        cell.yourVoteLabel.text = restaurant.vote?.rawValue
        cell.votesCountLabel.text = "\(restaurant.votesCount)"
        cell.votesCountLabel.isHidden = canIvote
        
        return cell
    }
}

extension RestaurantsViewController: CloudKitSynchronizerDelegate {
    
    func receivedResponse(with error: Error?) {
        let alertController: UIAlertController
        
        if let error = error {
            alertController = UIAlertController(title: "Error", message: "Error occured. Error: \(error)", preferredStyle: .alert)
        } else {
            alertController = UIAlertController(title: "Good!", message: "Everything gonna be ok", preferredStyle: .alert)
        }
        
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 3.0) {
            alertController.dismiss(animated: true, completion: nil)
        }
        
        synchronizer.fetchRecords { [weak self] (_, canIVote) in
            self?.canIvote = canIVote
            self?.updateTable()
        }
    }
}
