//
//  ViewController.swift
//  GoogleMap-Learning
//
//  Created by Ambarish Shivakumar on 11/02/25.
//

import UIKit
import MapKit

class ViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate {
    
    private var mapView: MKMapView!
    private var locationManager = CLLocationManager()
    private var searchCompleter = MKLocalSearchCompleter()
    private var searchResults: [MKLocalSearchCompletion] = []
    private let bottomSheetView = UIView()
    private var bottomSheetVC: BottomSheetViewController!
    private var tableView = UITableView()
    private let searchTextField = UITextField()
    
    var distanceLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = UIColor.black.withAlphaComponent(0.1)
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()
    
    var isRouteZoomed = false
    
    private var currentLocation: CLLocationCoordinate2D?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMapView()
        setupCurrentLocation()
       // setupBottomSheet()
        //setupTableView()
        setupLabel()
        
        locationManager.delegate = self
        mapView.delegate = self
        searchCompleter.delegate = self
        
        requestLocationPermission()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleDestinationSelection), name: NSNotification.Name("DestinationSelected"), object: nil)
    }
    
    private func setupMapView() {
        mapView = MKMapView(frame: view.bounds)
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        view.addSubview(mapView)
    }
    
    private func setupLabel() {
        
        view.addSubview(distanceLabel)
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            distanceLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            distanceLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            distanceLabel.widthAnchor.constraint(equalToConstant: 200),
            distanceLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    private func setupCurrentLocation() {
        guard let userLocation = locationManager.location?.coordinate else { return }
        
        let annotation = MKPointAnnotation()
        annotation.coordinate = userLocation
        annotation.title = "Current Location"
        mapView.addAnnotation(annotation)
        
        // Only apply initial zoom once
        if !self.isRouteZoomed {
            let region = MKCoordinateRegion(center: userLocation, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
            self.isRouteZoomed = true // Prevent resetting zoom later
        }
    }
    
    private func setupBottomSheet() {
        bottomSheetVC = BottomSheetViewController()
        
        if let sheet = bottomSheetVC.sheetPresentationController {
            let smallDetent = UISheetPresentationController.Detent.custom(identifier: .init("small")) { _ in
                return 150 // Small detent height
            }
            
            sheet.detents = [smallDetent, .medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            
            // Allows mapView interaction when in small detent
            sheet.largestUndimmedDetentIdentifier = .medium
        }
        
        present(bottomSheetVC, animated: true)
    }
    
    private func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if bottomSheetVC == nil {
            setupBottomSheet()
        }
    }

    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Set user location but do not override zoom after first set
        currentLocation = location.coordinate
        
        if !self.isRouteZoomed {
            let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
            self.isRouteZoomed = true
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        searchCompleter.queryFragment = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? string
        return true
    }
    
    func drawRoute(to destinationCoordinate: CLLocationCoordinate2D) {
        guard let userLocation = locationManager.location?.coordinate else {
            print("❌ User location not available!")
            return
        }
        
        let sourcePlacemark = MKPlacemark(coordinate: userLocation)
        let destinationPlacemark = MKPlacemark(coordinate: destinationCoordinate)
        
        mapView.annotations.forEach { annotation in
            if let title = annotation.title, title == "Destination" {
                mapView.removeAnnotation(annotation)
            }
        }
        
        let annotation = MKPointAnnotation()
        annotation.coordinate = destinationPlacemark.coordinate
        annotation.title = "Destination"
        
        // 🔹 Calculate distance
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let destinationCLLocation = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
        let distanceInMeters = userCLLocation.distance(from: destinationCLLocation)
        let distanceInKilometers = distanceInMeters / 1000.0
        
        distanceLabel.text = String(format: "Distance: %.2f km away", distanceInKilometers)
        distanceLabel.isHidden = false // floating label
        
        annotation.subtitle = String(format: "📏 %.2f km away", distanceInKilometers)
        mapView.addAnnotation(annotation) // when tapped on destination icon
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: sourcePlacemark)
        request.destination = MKMapItem(placemark: destinationPlacemark)
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            if let error = error {
                print("❌ Error calculating route: \(error.localizedDescription)")
                return
            }
            
            guard let route = response?.routes.first else {
                print("⚠️ No routes found!")
                return
            }
            
            self.mapView.removeOverlays(self.mapView.overlays)
            self.mapView.addOverlay(route.polyline)
            
            // ✅ Fit the route to screen WITHOUT forcing zoom after that
            let routeRect = route.polyline.boundingMapRect
            let edgePadding = UIEdgeInsets(top: 100, left: 50, bottom: 200, right: 50)
            self.mapView.setVisibleMapRect(routeRect, edgePadding: edgePadding, animated: true)
            
            // ✅ After setting the route, allow free movement
            self.isRouteZoomed = true
        }
    }
    
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        if animated { return } // Avoid re-centering when user drags the map
    }
}

extension ViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        tableView.reloadData()
    }
}

// MARK: - Bottom Sheet Controller
class BottomSheetViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, MKLocalSearchCompleterDelegate {
    
    private var tableView: UITableView!
    private var searchTextField: UITextField!
    let searchCompleter = MKLocalSearchCompleter()
    var searchResults: [MKLocalSearchCompletion] = []
    //private var searchResults: [String] = [] // Store address suggestions
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupUI()
        
        searchCompleter.delegate = self
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        view.addGestureRecognizer(panGesture)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapOutside))
        tapGesture.cancelsTouchesInView = false // Let touches pass through
        view.addGestureRecognizer(tapGesture)
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }
        return true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let sheet = self.sheetPresentationController {
            let currentDetent = sheet.selectedDetentIdentifier
            
            if currentDetent == .medium || currentDetent == .large {
                view.isUserInteractionEnabled = true
            } else {
                // Allow interaction for textField, but let touches pass through to the map
                for subview in view.subviews {
                    subview.isUserInteractionEnabled = true // Enable UI elements
                }
            }
        }
    }
    
    private func setupUI() {
        searchTextField = UITextField()
        searchTextField.placeholder = "Enter destination"
        searchTextField.borderStyle = .roundedRect
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.delegate = self
        view.addSubview(searchTextField)
        
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            searchTextField.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            searchTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: searchTextField.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        guard let address = textField.text, !address.isEmpty else {
            print("⚠️ Address field is empty!")
            return true
        }
        
        print("📌 Searching for address: \(address)")
        
        getCoordinates(forAddress: address) { coordinate in
            guard let coord = coordinate else {
                print("❌ Could not retrieve coordinates for \(address)")
                return
            }
            
            print("✅ Coordinates Found: \(coord.latitude), \(coord.longitude)")
            
            // Post notification with coordinates
            NotificationCenter.default.post(name: NSNotification.Name("DestinationSelected"), object: coord)
        }
        
        return true
    }

    func getCoordinates(forAddress address: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let geocoder = CLGeocoder()
        
        print("🔍 Geocoding address: \(address)")
        
        geocoder.geocodeAddressString(address) { (placemarks, error) in
            if let error = error {
                print("❌ Geocoding Error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let location = placemarks?.first?.location else {
                print("⚠️ No location found for \(address)")
                completion(nil)
                return
            }
            
            let coordinate = location.coordinate
            print("✅ Coordinates Found: \(coordinate.latitude), \(coordinate.longitude)")
            
            completion(coordinate)
            
            // Notify ViewController to draw the route
            NotificationCenter.default.post(name: NSNotification.Name("DestinationSelected"), object: coordinate)
        }
    }
    
    // MARK: - TableView Data Source
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.textLabel?.text = searchResults[indexPath.row].title
        return cell
    }
    
    // MARK: - TableView Selection
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedAddress = searchResults[indexPath.row]
        print("Selected Address: \(selectedAddress)")
       // print("Ambarish  ---- \(selectedAddre)")
        
        tableView.isHidden = true
        searchTextField.resignFirstResponder()
        
        // Convert address to coordinates
        getCoordinates(for: selectedAddress) { coordinate in
            print("AMBI - \(coordinate)")
        }
    }
    
    func getCoordinates(for address: MKLocalSearchCompletion, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let geocoder = CLGeocoder()
        let fullAddress = address.title + ", " + address.subtitle // Construct full address
        
        print("🗺 Geocoding Address: \(fullAddress)")
        
        geocoder.geocodeAddressString(fullAddress) { (placemarks, error) in
            if let error = error {
                print("❌ Geocoding Error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let location = placemarks?.first?.location else {
                print("⚠️ No location found for address: \(fullAddress)")
                completion(nil)
                return
            }
            
            let coordinate = location.coordinate
            print("✅ Coordinates Found: \(coordinate.latitude), \(coordinate.longitude)")
            
            // Call completion with the coordinate
            completion(coordinate)
            
            // Post notification
            NotificationCenter.default.post(name: NSNotification.Name("DestinationSelected"), object: coordinate)
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let query = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? string
        searchCompleter.queryFragment = query
        return true
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        tableView.reloadData()
        tableView.isHidden = searchResults.isEmpty
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Error fetching location suggestions: \(error.localizedDescription)")
    }
    
    func presentationControllerDidChangeSelectedDetentIdentifier(_ presentationController: UIPresentationController) {
        if let sheet = presentationController as? UISheetPresentationController {
            let currentDetent = sheet.selectedDetentIdentifier
            if currentDetent == .medium {
                self.view.isUserInteractionEnabled = true // Allow interactions
            } else if currentDetent == .large {
                self.view.isUserInteractionEnabled = true
            } else {
                self.view.isUserInteractionEnabled = false // Block interactions
            }
        }
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        view.endEditing(true)
    }
    
    @objc private func handleTapOutside(_ sender: UITapGestureRecognizer) {
        view.endEditing(true) // Dismiss keyboard when tapping outside
    }
}

extension ViewController {
    
    @objc private func handleDestinationSelection(notification: Notification) {
        print("🚀 Notification received: Destination selected!")
        
        guard let destinationCoordinate = notification.object as? CLLocationCoordinate2D else {
            print("⚠️ Invalid destinationCoordinate from notification!")
            return
        }
        
        print("✅ Destination coordinate: \(destinationCoordinate)")
        
        // Call drawRoute
        drawRoute(to: destinationCoordinate)
    }
    
    // MARK: - Overlay Renderer
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 5
            return renderer
        }
        return MKOverlayRenderer()
    }
}

extension ViewController {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil // Default blue dot for user location
        }
        
        let identifier = "CustomAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }
        
        // Set custom icons for annotations
        if annotation.title == "Current Location" {
            annotationView?.image = UIImage(named: "End_location_icon") // System image for user location
        } else if annotation.title == "Destination" {
            annotationView?.image = UIImage(named: "current_location_icon") // Custom icon for destination
        }
        
        annotationView?.frame.size = CGSize(width: 30, height: 30) // Adjust icon size
        return annotationView
    }
}




