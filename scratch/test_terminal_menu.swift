import Foundation
import Darwin

// Research script to test raw mode terminal input in Swift
func testRawInput() {
    var term = termios()
    tcgetattr(STDIN_FILENO, &term)
    
    let original = term
    
    // Disable canonical mode (buffered input) and echo
    term.c_lflag &= ~UInt(ECHO | ICANON)
    tcsetattr(STDIN_FILENO, TCSANOW, &term)
    
    print("Use Up/Down arrows to move. Press Enter to select. Press Q to quit.")
    
    var selected = 0
    let options = ["gemini-3-flash-preview:cloud", "Use some other model"]
    
    func render() {
        // Move up N lines to overwrite
        if selected >= 0 {
            print("\u{1b}[H\u{1b}[J", terminator: "") // Clear screen and home
        }
        for (i, opt) in options.enumerated() {
            if i == selected {
                print(" > [ x ] \(opt)")
            } else {
                print("   [   ] \(opt)")
            }
        }
    }
    
    render()
    
    var shouldQuit = false
    while !shouldQuit {
        var byte: UInt8 = 0
        read(STDIN_FILENO, &byte, 1)
        
        if byte == 0x1b { // Escape sequence
            var nextByte: UInt8 = 0
            read(STDIN_FILENO, &nextByte, 1)
            if nextByte == 0x5b { // [
                var arrowByte: UInt8 = 0
                read(STDIN_FILENO, &arrowByte, 1)
                if arrowByte == 0x41 { // Up
                    selected = max(0, selected - 1)
                    render()
                } else if arrowByte == 0x42 { // Down
                    selected = min(options.count - 1, selected + 1)
                    render()
                }
            }
        } else if byte == 0x0a { // Enter
            print("\nSelected: \(options[selected])")
            shouldQuit = true
        } else if byte == UInt8(ascii: "q") {
            shouldQuit = true
        }
    }
    
    // Restore original terminal state
    tcsetattr(STDIN_FILENO, TCSANOW, &original)
}

// Skip running in auto-mode as it's interactive, just a reference check for me.
// testRawInput()
print("Interactive research script written.")
