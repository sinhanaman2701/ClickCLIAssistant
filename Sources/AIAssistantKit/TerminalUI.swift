import Foundation
import Darwin

public enum TerminalUI {
    /// Displays an interactive selection menu in the terminal.
    /// - Parameters:
    ///   - options: List of options to choose from.
    ///   - title: Title displayed above the options.
    /// - Returns: The index of the selected option.
    public static func select(options: [String], title: String) -> Int {
        var originalTerm = termios()
        tcgetattr(STDIN_FILENO, &originalTerm)
        
        var rawTerm = originalTerm
        // Disable canonical mode (buffered input) and echo
        rawTerm.c_lflag &= ~UInt(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSANOW, &rawTerm)
        
        defer {
            // Ensure terminal state is restored on exit
            tcsetattr(STDIN_FILENO, TCSANOW, &originalTerm)
            print("\u{1b}[?25h", terminator: "") // Show cursor
        }
        
        print("\u{1b}[?25l", terminator: "") // Hide cursor
        
        var selectedIndex = 0
        let count = options.count
        
        func render() {
            // Move back to the start of the menu and clear
            if selectedIndex >= 0 {
                // We'll move up 'count' lines + title line
                let moveUp = count + 1
                print("\r\u{1b}[\(moveUp)A", terminator: "")
            }
            
            print("\u{1b}[1m\(title)\u{1b}[0m")
            for (i, option) in options.enumerated() {
                print("\u{1b}[2K", terminator: "") // Clear line
                if i == selectedIndex {
                    print(" \u{1b}[36m●\u{1b}[0m \(option)")
                } else {
                    print("   \(option)")
                }
            }
            fflush(stdout)
        }
        
        // Initial padding for the lines we'll overwrite
        print(title)
        for _ in options { print("") }
        
        render()
        
        var isDone = false
        while !isDone {
            var byte: UInt8 = 0
            let n = read(STDIN_FILENO, &byte, 1)
            guard n > 0 else { continue }
            
            if byte == 0x1b { // Escape sequence
                var nextByte: UInt8 = 0
                read(STDIN_FILENO, &nextByte, 1)
                if nextByte == 0x5b { // [
                    var arrowByte: UInt8 = 0
                    read(STDIN_FILENO, &arrowByte, 1)
                    if arrowByte == 0x41 { // Up
                        selectedIndex = (selectedIndex - 1 + count) % count
                        render()
                    } else if arrowByte == 0x42 { // Down
                        selectedIndex = (selectedIndex + 1) % count
                        render()
                    }
                }
            } else if byte == 10 || byte == 13 { // Enter (LF or CR)
                isDone = true
            } else if byte == 3 { // Ctrl+C
                tcsetattr(STDIN_FILENO, TCSANOW, &originalTerm)
                print("\u{1b}[?25h", terminator: "")
                exit(130)
            }
        }
        
        return selectedIndex
    }
}
