
import MetalKit

public class Renderer: NSObject, MTKViewDelegate {
    
    weak var view: MTKView!
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var library: MTLLibrary!
    var renderPipelineState: MTLRenderPipelineState!
    var uniformsBuffer: MTLBuffer!
    var meshes: [MTKMesh]!
    var texture: MTLTexture!
    var depthStencilState: MTLDepthStencilState!
    let vertexDescriptor = MTLVertexDescriptor()
    
    public init?(mtkView: MTKView) {
        super.init()
        
        view = mtkView
        view.clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1)
        view.colorPixelFormat = .bgra8Unorm
        initializeMetalObjects()
        createMatrixAndBuffers()
        createLibraryAndRenderPipeline()
        createAsset()
        
        view.delegate = self
        view.device = device
    }
    
    func initializeMetalObjects() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.newCommandQueue()
        view.depthStencilPixelFormat = MTLPixelFormat.depth32Float_Stencil8
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = MTLCompareFunction.less
        descriptor.isDepthWriteEnabled = true
        depthStencilState = device.newDepthStencilState(with: descriptor)
    }
    
    func createMatrixAndBuffers() {
        let scaled = scalingMatrix(1)
        let rotated = rotationMatrix(90, float3(0, 1, 0))
        let translated = translationMatrix(float3(0, -10, 0))
        let modelMatrix = matrix_multiply(matrix_multiply(translated, rotated), scaled)
        let cameraPosition = float3(0, 0, -50)
        let viewMatrix = translationMatrix(cameraPosition)
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let projMatrix = projectionMatrix(0.1, far: 100, aspect: aspect, fovy: 1)
        let modelViewProjectionMatrix = matrix_multiply(projMatrix, matrix_multiply(viewMatrix, modelMatrix))
        uniformsBuffer = device!.newBuffer(withLength: MemoryLayout<matrix_float4x4>.size, options: [])
        guard let uniformsBuffer = uniformsBuffer else {
            fatalError("Buffer cannot be created.")
        }
        let mvpMatrix = Uniforms(modelViewProjectionMatrix: modelViewProjectionMatrix)
        uniformsBuffer.contents().storeBytes(of: mvpMatrix, toByteOffset: 0, as: Uniforms.self)
    }
    
    func createLibraryAndRenderPipeline() {
        guard let path = Bundle.main.path(forResource: "Shaders", ofType: "metal") else {
            fatalError("Functions cannot be created.")
        }
        do {
            let input = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
            library = try device.newLibrary(withSource: input, options: MTLCompileOptions.init())
        }
        catch let error {
            fatalError("\(error)")
        }
        let vert_func = library.newFunction(withName: "vertex_func")
        let frag_func = library.newFunction(withName: "fragment_func")
        
// step 1: set up the render pipeline state
        
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].format = MTLVertexFormat.float3 // position
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].format = MTLVertexFormat.uChar4 // color
        vertexDescriptor.attributes[2].offset = 16
        vertexDescriptor.attributes[2].format = MTLVertexFormat.half2 // texture
        vertexDescriptor.attributes[3].offset = 20
        vertexDescriptor.attributes[3].format = MTLVertexFormat.float // occlusion
        vertexDescriptor.layouts[0].stride = 24
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor
        renderPipelineDescriptor.vertexFunction = vert_func
        renderPipelineDescriptor.fragmentFunction = frag_func
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        renderPipelineDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
        do {
            renderPipelineState = try device!.newRenderPipelineState(with: renderPipelineDescriptor)
        }
        catch let error {
            fatalError("\(error)")
        }
    }
    
    func createAsset() {
        
// step 2: set up the asset initialization
        
        let desc = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        var attribute = desc.attributes[0] as! MDLVertexAttribute
        attribute.name = MDLVertexAttributePosition
        attribute = desc.attributes[1] as! MDLVertexAttribute
        attribute.name = MDLVertexAttributeColor
        attribute = desc.attributes[2] as! MDLVertexAttribute
        attribute.name = MDLVertexAttributeTextureCoordinate
        attribute = desc.attributes[3] as! MDLVertexAttribute
        attribute.name = MDLVertexAttributeOcclusionValue
        let mtkBufferAllocator = MTKMeshBufferAllocator(device: device!)
        guard let url = Bundle.main.url(forResource: "Farmhouse", withExtension: "obj") else {
            fatalError("Resource not found.")
        }
        let asset = MDLAsset(url: url, vertexDescriptor: desc, bufferAllocator: mtkBufferAllocator)

//        let url1 = URL(string: "/Users/YourUsername/Desktop/exported.obj")
//        try! asset.export(to: url1!)
        
        let loader = MTKTextureLoader(device: device)
        guard let file = Bundle.main.path(forResource: "Farmhouse", ofType: "png") else {
            fatalError("Resource not found.")
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: file))
            texture = try loader.newTexture(with: data, options: nil)
        }
        catch let error {
            fatalError("\(error)")
        }
        
// step 3: set up MetalKit mesh and submesh objects
        
        guard let mesh = asset.object(at: 0) as? MDLMesh else {
            fatalError("Mesh not found.")
        }
        mesh.generateAmbientOcclusionVertexColors(withQuality: 1, attenuationFactor: 0.98, objectsToConsider: [mesh], vertexAttributeNamed: MDLVertexAttributeOcclusionValue)
        do {
            meshes = try MTKMesh.newMeshes(from: asset, device: device!, sourceMeshes: nil)
        }
        catch let error {
            fatalError("\(error)")
        }
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let descriptor = view.currentRenderPassDescriptor else {
            fatalError("The MTKView resources are not available.")
        }
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1)
        let commandBuffer = commandQueue!.commandBuffer()
        let commandEncoder = commandBuffer.renderCommandEncoder(with: descriptor)
        commandEncoder.setRenderPipelineState(renderPipelineState!)
        commandEncoder.setDepthStencilState(depthStencilState)
        commandEncoder.setCullMode(.back)
        commandEncoder.setFrontFacing(.counterClockwise)
        commandEncoder.setVertexBuffer(uniformsBuffer, offset: 0, at: 1)
        commandEncoder.setFragmentTexture(texture, at: 0)
        
// step 4: set up Metal rendering and drawing of meshes
        
        guard let mesh = meshes?.first else {
            fatalError("Mesh not found.")
        }
        let vertexBuffer = mesh.vertexBuffers[0]
        commandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, at: 0)
        guard let submesh = mesh.submeshes.first else {
            fatalError("Submesh not found.")
        }
        commandEncoder.drawIndexedPrimitives(submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
        
        commandEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
