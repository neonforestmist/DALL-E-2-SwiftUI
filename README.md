# 🖍️ DALL-E-2-SwiftUI: Getting Started
## You'll need these prerequisites:
- An OpenAI API Key
- Xcode and a device/simulator running on at least iOS 17+
## Steps
1. Clone the repo:
```
git clone https://github.com/neonforestmist/DALL-E-2-SwiftUI.git
```
2. Once you've opened up the Xcode project (in Dalle2/ folder), go to OpenAIService.swift file, and replace:
```swift
static var apiKey: String = "OPENAI_API_KEY"
```
...with your own api key.

3. Build + run the project! 🎉

## What it can do:
### Once given a valid api key, it can:
* Receive traditional image prompts:
  
  <img src="https://github.com/neonforestmist/DALL-E-2-SwiftUI/blob/0a56a9d1a942469274a907c1be6ea748639c7776/images/dalle-demo-1.webp" width=35%><br/>
* Inpaint (via drawing on parts of the image to edit):
 
  <img src="https://github.com/neonforestmist/DALL-E-2-SwiftUI/blob/0a56a9d1a942469274a907c1be6ea748639c7776/images/dalle-demo-2.webp" width=35%><br/>
* Outpaint (via being able to "zoom" out of an image and describe how the image should be filled):
  
  <img src="https://github.com/neonforestmist/DALL-E-2-SwiftUI/blob/1299faa7045c39b5b73c52ad04f4914cb060bdc7/images/dalle-demo-3.webp" width=35%><br/>
* Variations (making variations of an existing image):
  
  <img src="https://github.com/neonforestmist/DALL-E-2-SwiftUI/blob/2e953ee3ad0d972cd141f49555885e284e775dc6/images/dalle-demo-5.webp" width=35%><br/>

* You can also natively resize your images saved on your device to be able to use it with Dalle. 
  
  <img src="https://github.com/neonforestmist/DALL-E-2-SwiftUI/blob/0a56a9d1a942469274a907c1be6ea748639c7776/images/dalle-demo-4.webp" width=35%><br/>
## Cost per generation
> Table derived from OpenAI pricing.

| Model | Quality |256 x 256| 512 x 512 | 1024 x 1024 |
|:--------:|:--------:|:--------:|:--------:|:--------:|
| dall-e-2 | Standard | $0.016 | $0.018 | $0.02 |
