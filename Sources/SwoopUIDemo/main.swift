import Foundation
import SwoopUI

var body: some View {
    VStack {
        HStack {
            Color.red
            Color.green
            Color.blue
            Color.yellow
        }
        HStack {
            Color.yellow
            Color.red
            Color.green
            Color.blue
        }
        HStack {
            Color.blue
            Color.yellow
            Color.red
            Color.green
        }
        HStack {
            Color.green
            Color.blue
            Color.yellow
            Color.red
        }
    }
}

swoopUITest(CGSize(width: 120, height: 40), body)
