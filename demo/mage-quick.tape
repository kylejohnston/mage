# mage demo: quick defaults path
#
# Shows the fast, common-case flow: decline resize (the new default),
# accept WebP conversion, keep lossless (the new default). Three Enter
# presses and you're done.
#
# Run from inside this demo/ folder: vhs mage-quick.tape

Output mage-quick.gif
Output mage-quick.mp4

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

# Resize? — default is No, accept it
Tab
Sleep 500ms
Enter
Sleep 1s

# Convert to WebP? — default is Yes, accept it
Enter
Sleep 1s

# lossless / lossy — default is lossless, accept it
Enter
Sleep 2.5s
