//
//  InsulinTypeChooserView.swift
//  LoopKitUI
//
//  Created by Pete Schwamb on 12/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit

public struct InsulinTypeChooser: View {
    
    @Binding private var insulinType: InsulinType?
    
    let supportedInsulinTypes: [InsulinType?]
    
    public init(insulinType: Binding<InsulinType?>, supportedInsulinTypes: [InsulinType], allowUnsetInsulinType: Bool = false) {
        if allowUnsetInsulinType {
            self.supportedInsulinTypes = [InsulinType?](supportedInsulinTypes) + [nil]
        } else {
            self.supportedInsulinTypes = supportedInsulinTypes
        }
        self._insulinType = insulinType
    }

    public var body: some View {
        ForEach(supportedInsulinTypes, id: \.self) { insulinType in
            if let insulinType = insulinType {
                HStack {
                    ZStack {
                        Image(frameworkImage: "vial_color")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            // Use non-localized asset color key; Afrezza forced purple, others fallback to default insulin tint
                            .foregroundColor(insulinType == .afrezza ? Color(red: 149/255.0, green: 99/255.0, blue: 198/255.0) : (Color(frameworkColor: insulinType.assetColorKey) ?? Color.orange))
                        Image(frameworkImage: "vial")
                            .resizable()
                            .scaledToFit()
                    }
                    .padding([.trailing])
                    .frame(height: 70)
                    CheckmarkListItem(
                        title: Text(insulinType.title),
                        description: Text(insulinType.description),
                        isSelected: Binding(
                            get: { self.insulinType == insulinType },
                            set: { isSelected in
                                if isSelected {
                                    withAnimation {
                                        self.insulinType = insulinType
                                    }
                                }
                            }
                        )
                    )
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    CheckmarkListItem(
                        title: Text(LocalizedString("Unset", comment: "Title for selection when no insulin type is selected.")),
                        description: Text(LocalizedString("The currently selected fast acting insulin model will be used as a default.", comment: "Description for selection when no insulin type is selected.")),
                        isSelected: Binding(
                            get: { self.insulinType == nil },
                            set: { isSelected in
                                if isSelected {
                                    withAnimation {
                                        self.insulinType = nil
                                    }
                                }
                            }
                        )
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct InsulinTypeChooser_Previews: PreviewProvider {
    static var previews: some View {
        InsulinTypeChooser(insulinType: .constant(.novolog), supportedInsulinTypes: InsulinType.allCases)
    }
}

extension InsulinType {
    var image: UIImage? {
        return UIImage(frameworkImage: "vial")?.withTintColor(.red)
    }
}

// FreeAPS X: provide stable, non-localized color asset keys for insulin types
extension InsulinType {
    var assetColorKey: String {
        switch self {
        case .novolog:
            return "Novolog"
        case .humalog:
            return "Humalog"
        case .apidra:
            return "Apidra"
        case .fiasp:
            return "Fiasp"
        case .lyumjev:
            return "Lyumjev"
        case .afrezza:
            return "Afrezza"
        }
    }
}
