# mage demo: full tour of every prompt
#
# Overrides both defaults to show every branch: resize to a custom
# width, pick lossy instead of lossless, and set a custom quality.
#
# Run from inside this demo/ folder: vhs mage-full-tour.tape

Output mage-full-tour.gif
Output mage-full-tour.mp4

Require mage
Require gum
Require magick

Set Shell "bash"
Set FontSize 20
Set Width 1200
Set Height 650
Set Theme "Catppuccin Mocha"
Set Padding 20

# Hide
# Type "cd $(mktemp -d) && clear" Enter
# Type "magick -size 2400x1500 gradient:#4A90D9-#1A2744 demo.png" Enter
# Type "clear" Enter
# Show

Sleep 500ms
Type "mage demo.png"
Enter
Sleep 1.5s

# Resize? — default is No, press Tab to switch to Yes
Enter
Sleep 1s

# Resize to: — type a custom max-width
Type "1600"
Sleep 500ms
Enter
Sleep 1s

# Convert to WebP? — default is Yes, accept it
Enter
Sleep 1s

# lossless / lossy — default is lossless, move down to lossy
Down
Sleep 500ms
Enter
Sleep 1s

# Quality (blank = default 80) — type a custom value
Type "90"
Sleep 500ms
Enter
Sleep 6s
