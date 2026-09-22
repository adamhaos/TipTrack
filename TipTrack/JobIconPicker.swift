import SwiftUI
import UIKit

struct JobIconOption: Identifiable {
    let name: String
    let title: String
    var id: String { name }
}

struct JobIconGroup: Identifiable {
    let title: String
    let keywords: String
    let icons: [JobIconOption]
    var id: String { title }
}

enum JobIconCatalog {
    static let groups: [JobIconGroup] = [
        JobIconGroup(title: "Money & Tips", keywords: "money tip cash pay earnings bill credit bank currency", icons: [
            JobIconOption(name: "banknote", title: "Banknote"),
            JobIconOption(name: "banknote.fill", title: "Banknote · Solid"),
            JobIconOption(name: "dollarsign.circle", title: "Dollar"),
            JobIconOption(name: "dollarsign.circle.fill", title: "Dollar · Solid"),
            JobIconOption(name: "centsign.circle", title: "Cents"),
            JobIconOption(name: "centsign.circle.fill", title: "Cents · Solid"),
            JobIconOption(name: "creditcard", title: "Credit Card"),
            JobIconOption(name: "creditcard.fill", title: "Credit Card · Solid"),
            JobIconOption(name: "wallet.bifold", title: "Wallet"),
            JobIconOption(name: "wallet.bifold.fill", title: "Wallet · Solid"),
            JobIconOption(name: "wallet.pass", title: "Payment Pass"),
            JobIconOption(name: "wallet.pass.fill", title: "Payment Pass · Solid"),
            JobIconOption(name: "eurosign.circle", title: "Euro"),
            JobIconOption(name: "eurosign.circle.fill", title: "Euro · Solid"),
            JobIconOption(name: "sterlingsign.circle", title: "Pound"),
            JobIconOption(name: "sterlingsign.circle.fill", title: "Pound · Solid"),
            JobIconOption(name: "yensign.circle", title: "Yen"),
            JobIconOption(name: "yensign.circle.fill", title: "Yen · Solid"),
            JobIconOption(name: "bitcoinsign.circle", title: "Bitcoin"),
            JobIconOption(name: "bitcoinsign.circle.fill", title: "Bitcoin · Solid"),
            JobIconOption(name: "cart", title: "Shopping Cart"),
            JobIconOption(name: "cart.fill", title: "Shopping Cart · Solid"),
            JobIconOption(name: "bag", title: "Shopping Bag"),
            JobIconOption(name: "bag.fill", title: "Shopping Bag · Solid"),
            JobIconOption(name: "basket", title: "Basket"),
            JobIconOption(name: "basket.fill", title: "Basket · Solid"),
            JobIconOption(name: "gift", title: "Gift"),
            JobIconOption(name: "gift.fill", title: "Gift · Solid"),
            JobIconOption(name: "tag", title: "Price Tag"),
            JobIconOption(name: "tag.fill", title: "Price Tag · Solid"),
            JobIconOption(name: "percent", title: "Percentage"),
            JobIconOption(name: "chart.line.uptrend.xyaxis", title: "Earnings"),
            JobIconOption(name: "briefcase", title: "Work"),
            JobIconOption(name: "briefcase.fill", title: "Work · Solid"),
        ]),
        JobIconGroup(title: "Food & Drinks", keywords: "restaurant server waiter waitress bartender bar cafe coffee food kitchen cook bakery drink dining", icons: [
            JobIconOption(name: "fork.knife", title: "Restaurant"),
            JobIconOption(name: "fork.knife.circle", title: "Dining"),
            JobIconOption(name: "fork.knife.circle.fill", title: "Dining · Solid"),
            JobIconOption(name: "wineglass", title: "Wine Glass"),
            JobIconOption(name: "wineglass.fill", title: "Wine Glass · Solid"),
            JobIconOption(name: "cup.and.saucer", title: "Coffee"),
            JobIconOption(name: "cup.and.saucer.fill", title: "Coffee · Solid"),
            JobIconOption(name: "cup.and.heat.waves", title: "Hot Drink"),
            JobIconOption(name: "cup.and.heat.waves.fill", title: "Hot Drink · Solid"),
            JobIconOption(name: "mug", title: "Mug"),
            JobIconOption(name: "mug.fill", title: "Mug · Solid"),
            JobIconOption(name: "takeoutbag.and.cup.and.straw", title: "Takeout"),
            JobIconOption(name: "takeoutbag.and.cup.and.straw.fill", title: "Takeout · Solid"),
            JobIconOption(name: "waterbottle", title: "Bottle"),
            JobIconOption(name: "waterbottle.fill", title: "Bottle · Solid"),
            JobIconOption(name: "carrot", title: "Carrot"),
            JobIconOption(name: "carrot.fill", title: "Carrot · Solid"),
            JobIconOption(name: "fish", title: "Fish"),
            JobIconOption(name: "fish.fill", title: "Fish · Solid"),
            JobIconOption(name: "birthday.cake", title: "Cake"),
            JobIconOption(name: "birthday.cake.fill", title: "Cake · Solid"),
            JobIconOption(name: "frying.pan", title: "Frying Pan"),
            JobIconOption(name: "frying.pan.fill", title: "Frying Pan · Solid"),
            JobIconOption(name: "flame", title: "Cooking"),
            JobIconOption(name: "flame.fill", title: "Cooking · Solid"),
            JobIconOption(name: "leaf", title: "Fresh Food"),
            JobIconOption(name: "leaf.fill", title: "Fresh Food · Solid"),
            JobIconOption(name: "oven", title: "Oven"),
            JobIconOption(name: "oven.fill", title: "Oven · Solid"),
            JobIconOption(name: "refrigerator", title: "Refrigerator"),
            JobIconOption(name: "refrigerator.fill", title: "Refrigerator · Solid"),
            JobIconOption(name: "tray", title: "Serving Tray"),
            JobIconOption(name: "tray.fill", title: "Serving Tray · Solid"),
            JobIconOption(name: "bell", title: "Service Bell"),
            JobIconOption(name: "bell.fill", title: "Service Bell · Solid"),
        ]),
        JobIconGroup(title: "Hotels & Buildings", keywords: "hotel motel concierge doorman bellhop building hospitality reception lodging resort shop store home property", icons: [
            JobIconOption(name: "building", title: "Building"),
            JobIconOption(name: "building.fill", title: "Building · Solid"),
            JobIconOption(name: "building.2", title: "City Buildings"),
            JobIconOption(name: "building.2.fill", title: "City Buildings · Solid"),
            JobIconOption(name: "building.2.crop.circle", title: "City"),
            JobIconOption(name: "building.2.crop.circle.fill", title: "City · Solid"),
            JobIconOption(name: "building.classical.columns", title: "Classical Building"),
            JobIconOption(name: "building.classical.columns.fill", title: "Classical Building · Solid"),
            JobIconOption(name: "storefront", title: "Storefront"),
            JobIconOption(name: "storefront.fill", title: "Storefront · Solid"),
            JobIconOption(name: "house", title: "House"),
            JobIconOption(name: "house.fill", title: "House · Solid"),
            JobIconOption(name: "bed.double", title: "Hotel Bed"),
            JobIconOption(name: "bed.double.fill", title: "Hotel Bed · Solid"),
            JobIconOption(name: "sofa", title: "Lounge"),
            JobIconOption(name: "sofa.fill", title: "Lounge · Solid"),
            JobIconOption(name: "chair", title: "Chair"),
            JobIconOption(name: "chair.fill", title: "Chair · Solid"),
            JobIconOption(name: "chair.lounge", title: "Lounge Chair"),
            JobIconOption(name: "chair.lounge.fill", title: "Lounge Chair · Solid"),
            JobIconOption(name: "door.left.hand.closed", title: "Door"),
            JobIconOption(name: "key", title: "Key"),
            JobIconOption(name: "key.fill", title: "Key · Solid"),
            JobIconOption(name: "signpost.right", title: "Directions"),
            JobIconOption(name: "signpost.right.fill", title: "Directions · Solid"),
            JobIconOption(name: "mappin.and.ellipse", title: "Location"),
            JobIconOption(name: "tent", title: "Camping"),
            JobIconOption(name: "tent.fill", title: "Camping · Solid"),
            JobIconOption(name: "beach.umbrella", title: "Resort"),
            JobIconOption(name: "beach.umbrella.fill", title: "Resort · Solid"),
            JobIconOption(name: "tree", title: "Garden"),
            JobIconOption(name: "tree.fill", title: "Garden · Solid"),
        ]),
        JobIconGroup(title: "Transport & Delivery", keywords: "car driver taxi rideshare uber lyft valet parking delivery courier bike truck transport boat", icons: [
            JobIconOption(name: "car", title: "Car"),
            JobIconOption(name: "car.fill", title: "Car · Solid"),
            JobIconOption(name: "car.side", title: "Car Side"),
            JobIconOption(name: "car.side.fill", title: "Car Side · Solid"),
            JobIconOption(name: "car.rear", title: "Car Rear"),
            JobIconOption(name: "car.rear.fill", title: "Car Rear · Solid"),
            JobIconOption(name: "car.2", title: "Two Cars"),
            JobIconOption(name: "car.2.fill", title: "Two Cars · Solid"),
            JobIconOption(name: "car.side.front.open", title: "Car Door"),
            JobIconOption(name: "car.side.front.open.fill", title: "Car Door · Solid"),
            JobIconOption(name: "car.top.door.front.left.open", title: "Valet"),
            JobIconOption(name: "car.top.door.front.left.open.fill", title: "Valet · Solid"),
            JobIconOption(name: "steeringwheel", title: "Steering Wheel"),
            JobIconOption(name: "bolt.car", title: "Electric Car"),
            JobIconOption(name: "bolt.car.fill", title: "Electric Car · Solid"),
            JobIconOption(name: "truck.box", title: "Delivery Truck"),
            JobIconOption(name: "truck.box.fill", title: "Delivery Truck · Solid"),
            JobIconOption(name: "truck.pickup.side", title: "Pickup Truck"),
            JobIconOption(name: "truck.pickup.side.fill", title: "Pickup Truck · Solid"),
            JobIconOption(name: "shippingbox", title: "Package"),
            JobIconOption(name: "shippingbox.fill", title: "Package · Solid"),
            JobIconOption(name: "bicycle", title: "Bicycle"),
            JobIconOption(name: "scooter", title: "Scooter"),
            JobIconOption(name: "bus", title: "Bus"),
            JobIconOption(name: "bus.fill", title: "Bus · Solid"),
            JobIconOption(name: "tram", title: "Tram"),
            JobIconOption(name: "tram.fill", title: "Tram · Solid"),
            JobIconOption(name: "airplane", title: "Airplane"),
            JobIconOption(name: "sailboat", title: "Sailboat"),
            JobIconOption(name: "sailboat.fill", title: "Sailboat · Solid"),
            JobIconOption(name: "ferry", title: "Ferry"),
            JobIconOption(name: "ferry.fill", title: "Ferry · Solid"),
            JobIconOption(name: "car.ferry", title: "Car Ferry"),
            JobIconOption(name: "car.ferry.fill", title: "Car Ferry · Solid"),
            JobIconOption(name: "fuelpump", title: "Fuel Pump"),
            JobIconOption(name: "fuelpump.fill", title: "Fuel Pump · Solid"),
        ]),
        JobIconGroup(title: "People & Service", keywords: "server waiter waitress bartender service staff hospitality customer team person help hand", icons: [
            JobIconOption(name: "person", title: "Person"),
            JobIconOption(name: "person.fill", title: "Person · Solid"),
            JobIconOption(name: "person.2", title: "Team"),
            JobIconOption(name: "person.2.fill", title: "Team · Solid"),
            JobIconOption(name: "person.3", title: "Group"),
            JobIconOption(name: "person.3.fill", title: "Group · Solid"),
            JobIconOption(name: "person.crop.circle", title: "Staff"),
            JobIconOption(name: "person.crop.circle.fill", title: "Staff · Solid"),
            JobIconOption(name: "person.crop.square", title: "Staff Badge"),
            JobIconOption(name: "person.crop.square.fill", title: "Staff Badge · Solid"),
            JobIconOption(name: "person.bust", title: "Portrait"),
            JobIconOption(name: "person.bust.fill", title: "Portrait · Solid"),
            JobIconOption(name: "figure.stand", title: "Standing"),
            JobIconOption(name: "figure.walk", title: "Walking"),
            JobIconOption(name: "hand.wave", title: "Welcome"),
            JobIconOption(name: "hand.wave.fill", title: "Welcome · Solid"),
            JobIconOption(name: "hand.thumbsup", title: "Great Service"),
            JobIconOption(name: "hand.thumbsup.fill", title: "Great Service · Solid"),
            JobIconOption(name: "hand.raised", title: "Helping Hand"),
            JobIconOption(name: "hand.raised.fill", title: "Helping Hand · Solid"),
            JobIconOption(name: "heart", title: "Care"),
            JobIconOption(name: "heart.fill", title: "Care · Solid"),
            JobIconOption(name: "star", title: "Star Service"),
            JobIconOption(name: "star.fill", title: "Star Service · Solid"),
            JobIconOption(name: "face.smiling", title: "Smile"),
        ]),
        JobIconGroup(title: "Beauty, Care & Trades", keywords: "salon barber hair stylist beauty spa massage nail manicure cleaning cleaner housekeeping repair handy services pets dog groomer", icons: [
            JobIconOption(name: "scissors", title: "Scissors"),
            JobIconOption(name: "scissors.circle", title: "Barber"),
            JobIconOption(name: "scissors.circle.fill", title: "Barber · Solid"),
            JobIconOption(name: "comb", title: "Comb"),
            JobIconOption(name: "comb.fill", title: "Comb · Solid"),
            JobIconOption(name: "sparkles", title: "Beauty"),
            JobIconOption(name: "paintbrush", title: "Brush"),
            JobIconOption(name: "paintbrush.fill", title: "Brush · Solid"),
            JobIconOption(name: "paintbrush.pointed", title: "Detail Brush"),
            JobIconOption(name: "paintbrush.pointed.fill", title: "Detail Brush · Solid"),
            JobIconOption(name: "paintpalette", title: "Palette"),
            JobIconOption(name: "paintpalette.fill", title: "Palette · Solid"),
            JobIconOption(name: "eyebrow", title: "Eyebrow"),
            JobIconOption(name: "eye", title: "Eye"),
            JobIconOption(name: "eye.fill", title: "Eye · Solid"),
            JobIconOption(name: "mustache", title: "Mustache"),
            JobIconOption(name: "mustache.fill", title: "Mustache · Solid"),
            JobIconOption(name: "shower", title: "Shower"),
            JobIconOption(name: "shower.fill", title: "Shower · Solid"),
            JobIconOption(name: "bathtub", title: "Bath"),
            JobIconOption(name: "bathtub.fill", title: "Bath · Solid"),
            JobIconOption(name: "bubbles.and.sparkles", title: "Cleaning"),
            JobIconOption(name: "bubbles.and.sparkles.fill", title: "Cleaning · Solid"),
            JobIconOption(name: "washer", title: "Laundry"),
            JobIconOption(name: "washer.fill", title: "Laundry · Solid"),
            JobIconOption(name: "dryer", title: "Dryer"),
            JobIconOption(name: "dryer.fill", title: "Dryer · Solid"),
            JobIconOption(name: "tshirt", title: "Clothing"),
            JobIconOption(name: "tshirt.fill", title: "Clothing · Solid"),
            JobIconOption(name: "hanger", title: "Hanger"),
            JobIconOption(name: "hammer", title: "Hammer"),
            JobIconOption(name: "hammer.fill", title: "Hammer · Solid"),
            JobIconOption(name: "wrench.and.screwdriver", title: "Tools"),
            JobIconOption(name: "wrench.and.screwdriver.fill", title: "Tools · Solid"),
            JobIconOption(name: "wrench.adjustable", title: "Wrench"),
            JobIconOption(name: "wrench.adjustable.fill", title: "Wrench · Solid"),
            JobIconOption(name: "pawprint", title: "Pets"),
            JobIconOption(name: "pawprint.fill", title: "Pets · Solid"),
            JobIconOption(name: "dog", title: "Dog"),
            JobIconOption(name: "dog.fill", title: "Dog · Solid"),
            JobIconOption(name: "cat", title: "Cat"),
            JobIconOption(name: "cat.fill", title: "Cat · Solid"),
            JobIconOption(name: "drop", title: "Water"),
            JobIconOption(name: "drop.fill", title: "Water · Solid"),
        ]),
        JobIconGroup(title: "Events & Recreation", keywords: "entertainment music musician performer dj dance tour guide fitness trainer sports event party casino recreation", icons: [
            JobIconOption(name: "music.note", title: "Music"),
            JobIconOption(name: "guitars", title: "Guitar"),
            JobIconOption(name: "guitars.fill", title: "Guitar · Solid"),
            JobIconOption(name: "headphones", title: "DJ"),
            JobIconOption(name: "theatermasks", title: "Theater"),
            JobIconOption(name: "theatermasks.fill", title: "Theater · Solid"),
            JobIconOption(name: "ticket", title: "Ticket"),
            JobIconOption(name: "ticket.fill", title: "Ticket · Solid"),
            JobIconOption(name: "party.popper", title: "Party"),
            JobIconOption(name: "party.popper.fill", title: "Party · Solid"),
            JobIconOption(name: "balloon", title: "Balloon"),
            JobIconOption(name: "balloon.fill", title: "Balloon · Solid"),
            JobIconOption(name: "camera", title: "Photography"),
            JobIconOption(name: "camera.fill", title: "Photography · Solid"),
            JobIconOption(name: "map", title: "Tour Guide"),
            JobIconOption(name: "map.fill", title: "Tour Guide · Solid"),
            JobIconOption(name: "binoculars", title: "Tours"),
            JobIconOption(name: "binoculars.fill", title: "Tours · Solid"),
            JobIconOption(name: "figure.dance", title: "Dancing"),
            JobIconOption(name: "figure.pool.swim", title: "Swimming"),
            JobIconOption(name: "figure.yoga", title: "Yoga"),
            JobIconOption(name: "dumbbell", title: "Fitness"),
            JobIconOption(name: "dumbbell.fill", title: "Fitness · Solid"),
            JobIconOption(name: "sportscourt", title: "Sports"),
            JobIconOption(name: "sportscourt.fill", title: "Sports · Solid"),
            JobIconOption(name: "gamecontroller", title: "Games"),
            JobIconOption(name: "gamecontroller.fill", title: "Games · Solid"),
            JobIconOption(name: "dice", title: "Dice"),
            JobIconOption(name: "dice.fill", title: "Dice · Solid"),
            JobIconOption(name: "suit.spade", title: "Cards"),
            JobIconOption(name: "suit.spade.fill", title: "Cards · Solid"),
        ]),
    ]

    // Cache the choices available on this device so older iOS versions never show empty icons.
    static let availableGroups = groups.map { group in
        JobIconGroup(title: group.title, keywords: group.keywords,
                     icons: group.icons.filter { UIImage(systemName: $0.name) != nil })
    }

    static func symbolName(for name: String) -> String {
        UIImage(systemName: name) == nil ? "briefcase.fill" : name
    }

    static func title(for name: String) -> String {
        groups.flatMap(\.icons).first { $0.name == name }?.title ?? "Work"
    }
}

extension Job {
    var iconSymbolName: String {
        JobIconCatalog.symbolName(for: iconName)
    }
}

struct JobIconPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    let color: Color
    @State private var search = ""

    private var matchingGroups: [JobIconGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return JobIconCatalog.availableGroups.compactMap { group in
            let categoryMatches = (group.title + " " + group.keywords).localizedCaseInsensitiveContains(query)
            let icons = group.icons.filter {
                query.isEmpty || categoryMatches
                    || ($0.title + " " + $0.name).localizedCaseInsensitiveContains(query)
            }
            return icons.isEmpty ? nil : JobIconGroup(title: group.title, keywords: group.keywords, icons: icons)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(matchingGroups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.title).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                            ForEach(group.icons) { icon in
                                Button {
                                    selection = icon.name
                                    dismiss()
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: icon.name)
                                            .font(.system(size: 25))
                                            .frame(height: 32)
                                            .foregroundStyle(color)
                                        Text(icon.title)
                                            .font(.caption2)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .frame(minHeight: 30)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity)
                                    .background(color.opacity(selection == icon.name ? 0.2 : 0.06), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selection == icon.name ? color : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(icon.title)
                                .accessibilityValue(selection == icon.name ? "Selected" : "")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .overlay {
            if matchingGroups.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("Choose Job Icon")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search icons or work, like valet or coffee")
    }
}
