# mage demo: batch — multiple files in one run
#
# Passes three files as args; the prompts only run once and apply to
# every file, each processed and reported independently.
#
# Run from inside this demo/ folder: vhs mage-batch.tape

Output mage-batch.gif
Output mage-batch.mp4

Require mage
Require gum
Require magick

Set Shell "bash"
Set FontSize 20
Set Width 1200
Set Height 650
Set Theme "Catppuccin Mocha"
Set Padding 20

Hide
Type "cd $(mktemp -d) && clear" Enter
Type "magick -size 2400x1500 gradient:#4A90D9-#1A2744 demo1.png" Enter
Type "magick -size 2400x1500 gradient:#E07A5F-#3D1E1A demo2.png" Enter
Type "magick -size 2400x1500 gradient:#81B29A-#1B2E28 demo3.png" Enter
Type "clear" Enter
Show

Sleep 500ms
Type "mage demo1.png demo2.png demo3.png"
Enter
Sleep 1.5s

# Resize? — default is No, accept it
Enter
Sleep 1s

# Convert to WebP? — default is Yes, accept it
Enter
Sleep 1s

# lossless / lossy — default is lossless, accept it
Enter
Sleep 3s
