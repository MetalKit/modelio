
import MetalKit
import PlaygroundSupport

let view = MTKView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
let renderer = Renderer(mtkView: view)
view.delegate = renderer
PlaygroundPage.current.liveView = view
