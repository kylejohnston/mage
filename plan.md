Context: I've been using OptImage to optimize and resize images. The app is supported in the latest version of macOS (v27, public beta)

My primary use cases:
- convert images to webp so they're optimized for the web
- resize images (large screenshots) by either percentage or max width

Goal: I'd like to explore a CLI and/or script-based workflow to replace OptImage

Notes:  
- I've tried cwebp – I like the output, but it's cumbersome to pass in paths, especially for images outside the current directory. Also, I don't know if it supports resizing.
- macOS supports folder automations, but I'd like to have this work in any folder
- I use a launcher called [Tuna](https://tunaformac.com/docs/start-here), which allows me to run shell scripts against a file, groups of files, or folder
- It would be cool to be able to supply an input path, select options (resize → options, lossy/lossless) in a cli workflow, then run the script as the final step. The tool would infer the output path based on the input path
- there may be other workflows or options that I’m not thinking of; feel free to push on any assumptions or blind spots
