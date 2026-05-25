<script setup>
import { ref, onMounted, onUnmounted, watch } from "vue"
import * as THREE from "three"
import { STLLoader } from "three/addons/loaders/STLLoader.js"
import { ThreeMFLoader } from "three/addons/loaders/3MFLoader.js"
import { OrbitControls } from "three/addons/controls/OrbitControls.js"
import { TransformControls } from "three/addons/controls/TransformControls.js"
import { STLExporter } from "three/addons/exporters/STLExporter.js"

const props = defineProps({
  url: { type: String, default: null },
  fileType: { type: String, default: "stl" },
  bedWidth: { type: Number, default: 256 },
  bedDepth: { type: Number, default: 256 },
  assetId: { type: [String, Number], default: null },
  projectId: { type: [String, Number], default: null }
})

const emit = defineEmits(["file-dropped", "asset-deleted"])

const container = ref(null)
const loadError = ref("")
const transformMode = ref("translate")
const modelDims = ref(null)
const dragging = ref(false)

// Multi-plate state
const plates = ref([{ id: 1, name: 'Plate 1' }])
const currentPlateId = ref(1)
const plateObjectStore = {} // plateId -> [THREE.Object3D]
const plateRestored = ref(false)
let nextPlateId = 2
let unmounted = false

// Track URLs currently being loaded to prevent timing-window duplicates
const loadingUrls = new Set()

let renderer, scene, camera, controls, transformCtrl, animationId, resizeObs
let selectedObject = null
const objects = [] // current plate's objects

// Undo/redo state — tracks full scene snapshots (position, rotation, scale, and object presence)
const undoStack = []
const redoStack = []
function saveState() {
  const snapshot = objects.map(obj => ({
    obj,
    pos: obj.position.clone(),
    quat: obj.quaternion.clone(),
    scale: obj.scale.clone(),
    inScene: true
  }))
  undoStack.push(snapshot)
  if (undoStack.length > 30) undoStack.shift()
  redoStack.length = 0
}
function restoreSnapshot(snap) {
  // Remove all current objects from scene
  for (const obj of [...objects]) {
    transformCtrl.detach()
    scene.remove(obj)
  }
  objects.length = 0
  // Restore snapshot objects
  for (const s of snap) {
    s.obj.position.copy(s.pos)
    s.obj.quaternion.copy(s.quat)
    s.obj.scale.copy(s.scale)
    if (s.inScene) {
      scene.add(s.obj)
      objects.push(s.obj)
    }
  }
  if (objects.length > 0) {
    selectObject(objects[objects.length - 1])
  } else {
    selectedObject = null
    modelDims.value = null
  }
}
function undo() {
  if (undoStack.length === 0) return
  const cur = objects.map(obj => ({ obj, pos: obj.position.clone(), quat: obj.quaternion.clone(), scale: obj.scale.clone(), inScene: true }))
  redoStack.push(cur)
  restoreSnapshot(undoStack.pop())
  saveTransforms()
}
function redo() {
  if (redoStack.length === 0) return
  const cur = objects.map(obj => ({ obj, pos: obj.position.clone(), quat: obj.quaternion.clone(), scale: obj.scale.clone(), inScene: true }))
  undoStack.push(cur)
  restoreSnapshot(redoStack.pop())
  saveTransforms()
}

function init() {
  const el = container.value
  if (!el) return

  const w = props.bedWidth
  const d = props.bedDepth

  scene = new THREE.Scene()
  scene.background = new THREE.Color(0x2a2a2a)

  camera = new THREE.PerspectiveCamera(45, el.clientWidth / el.clientHeight, 0.1, 5000)
  camera.position.set(w * 0.7, w * 0.5, w * 0.9)

  renderer = new THREE.WebGLRenderer({ antialias: true })
  renderer.setSize(el.clientWidth, el.clientHeight)
  renderer.setPixelRatio(window.devicePixelRatio)
  renderer.shadowMap.enabled = true
  el.appendChild(renderer.domElement)

  // Orbit
  controls = new OrbitControls(camera, renderer.domElement)
  controls.enableDamping = true
  controls.target.set(w / 2, 0, d / 2)
  controls.maxPolarAngle = Math.PI / 2 + 0.05
  controls.update()

  // Transform
  transformCtrl = new TransformControls(camera, renderer.domElement)
  transformCtrl.addEventListener("dragging-changed", (e) => {
    controls.enabled = !e.value
  })
  transformCtrl.addEventListener("dragging-changed", (e) => {
    if (e.value) saveState() // save before drag starts
    else saveTransforms() // persist when drag ends
  })
  transformCtrl.addEventListener("objectChange", () => {
    if (selectedObject) {
      // Keep on bed (Y >= 0)
      const box = new THREE.Box3().setFromObject(selectedObject)
      if (box.min.y < 0) selectedObject.position.y -= box.min.y
      updateDimensions()
    }
  })
  scene.add(transformCtrl.getHelper())

  // Lighting
  scene.add(new THREE.AmbientLight(0xffffff, 0.5))
  const mainLight = new THREE.DirectionalLight(0xffffff, 0.8)
  mainLight.position.set(w, w, w)
  mainLight.castShadow = true
  scene.add(mainLight)
  const fillLight = new THREE.DirectionalLight(0xffffff, 0.3)
  fillLight.position.set(-w, w * 0.5, -w)
  scene.add(fillLight)

  buildPlate(w, d)
  buildAxes(w)

  // Click to select objects
  renderer.domElement.addEventListener("pointerdown", onPointerDown)

  animate()
}

function buildPlate(w, d) {
  // Platform
  const plateGeo = new THREE.PlaneGeometry(w, d)
  const plateMat = new THREE.MeshPhongMaterial({ color: 0x3a3a3a, specular: 0x111111, shininess: 20, side: THREE.DoubleSide })
  const plate = new THREE.Mesh(plateGeo, plateMat)
  plate.rotation.x = -Math.PI / 2
  plate.position.set(w / 2, -0.05, d / 2)
  plate.receiveShadow = true
  plate.userData.isBed = true
  scene.add(plate)

  // Grid
  const grid = new THREE.GridHelper(w, Math.round(w / 10), 0x555555, 0x444444)
  grid.position.set(w / 2, 0, d / 2)
  grid.userData.isBed = true
  scene.add(grid)

  // Border
  const pts = [new THREE.Vector3(0,0.05,0), new THREE.Vector3(w,0.05,0), new THREE.Vector3(w,0.05,d), new THREE.Vector3(0,0.05,d), new THREE.Vector3(0,0.05,0)]
  const border = new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), new THREE.LineBasicMaterial({ color: 0x666666 }))
  border.userData.isBed = true
  scene.add(border)
}

function buildAxes(w) {
  const len = w * 0.12
  const makeAxis = (end, color) => {
    const geo = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(0,0.2,0), end])
    const line = new THREE.Line(geo, new THREE.LineBasicMaterial({ color }))
    line.userData.isBed = true
    scene.add(line)
  }
  makeAxis(new THREE.Vector3(len, 0.2, 0), 0xff4444)
  makeAxis(new THREE.Vector3(0, len, 0), 0x44ff44)
  makeAxis(new THREE.Vector3(0, 0.2, len), 0x4444ff)
}

function rebuildBed(w, d) {
  const toRemove = scene.children.filter(c => c.userData.isBed)
  for (const obj of toRemove) {
    scene.remove(obj)
    if (obj.geometry) obj.geometry.dispose()
    if (obj.material) obj.material.dispose()
  }
  buildPlate(w, d)
  buildAxes(w)
  controls.target.set(w / 2, 0, d / 2)
  controls.update()
}

function animate() {
  animationId = requestAnimationFrame(animate)
  controls?.update()
  renderer?.render(scene, camera)
}

// --- Object selection via raycasting ---
function onPointerDown(event) {
  const el = container.value
  if (!el) return
  const rect = el.getBoundingClientRect()
  const mouse = new THREE.Vector2(
    ((event.clientX - rect.left) / rect.width) * 2 - 1,
    -((event.clientY - rect.top) / rect.height) * 2 + 1
  )
  const raycaster = new THREE.Raycaster()
  raycaster.setFromCamera(mouse, camera)

  const meshes = []
  for (const obj of objects) {
    obj.traverse((c) => { if (c.isMesh) meshes.push(c) })
  }
  const hits = raycaster.intersectObjects(meshes, false)
  if (hits.length > 0) {
    // Find parent group
    let target = hits[0].object
    while (target.parent && !objects.includes(target)) target = target.parent
    if (objects.includes(target)) selectObject(target)
  }
}

function selectObject(obj) {
  selectedObject = obj
  transformCtrl.attach(obj)
  updateDimensions()
}

function updateDimensions() {
  if (!selectedObject) { modelDims.value = null; return }
  const box = new THREE.Box3().setFromObject(selectedObject)
  const size = box.getSize(new THREE.Vector3())
  const pos = selectedObject.position
  const rot = selectedObject.rotation
  const scl = selectedObject.scale
  modelDims.value = {
    x: size.x.toFixed(1), y: size.y.toFixed(1), z: size.z.toFixed(1),
    px: pos.x.toFixed(1), py: pos.y.toFixed(1), pz: pos.z.toFixed(1),
    rx: THREE.MathUtils.radToDeg(rot.x).toFixed(1),
    ry: THREE.MathUtils.radToDeg(rot.y).toFixed(1),
    rz: THREE.MathUtils.radToDeg(rot.z).toFixed(1),
    sx: scl.x.toFixed(2), sy: scl.y.toFixed(2), sz: scl.z.toFixed(2)
  }
}

// --- Transform persistence via localStorage (per-project, keyed by assetId) ---
function getStorageKey() {
  return props.projectId ? `gemslice_transforms_project_${props.projectId}_plate_${currentPlateId.value}` : null
}

function saveTransforms() {
  const key = getStorageKey()
  if (!key) return
  const data = {}
  for (const obj of objects) {
    const id = obj.userData.assetId
    if (!id) continue
    data[id] = {
      px: obj.position.x, py: obj.position.y, pz: obj.position.z,
      qx: obj.quaternion.x, qy: obj.quaternion.y, qz: obj.quaternion.z, qw: obj.quaternion.w,
      sx: obj.scale.x, sy: obj.scale.y, sz: obj.scale.z
    }
  }
  try { localStorage.setItem(key, JSON.stringify(data)) } catch {}
  savePlateConfig()
}

// --- Plate persistence ---
function savePlateConfig() {
  if (!props.projectId) return
  const pkey = `gemslice_plates_project_${props.projectId}`
  const config = {
    plates: plates.value,
    nextPlateId,
    activePlateId: currentPlateId.value,
    plateAssets: {}
  }
  for (const plate of plates.value) {
    const objs = plate.id === currentPlateId.value ? objects : (plateObjectStore[plate.id] || [])
    config.plateAssets[plate.id] = objs.map(obj => ({
      sourceUrl: obj.userData.sourceUrl || null,
      fileType: obj.userData.fileType || 'stl',
      assetId: obj.userData.assetId || null,
      px: obj.position.x, py: obj.position.y, pz: obj.position.z,
      qx: obj.quaternion.x, qy: obj.quaternion.y, qz: obj.quaternion.z, qw: obj.quaternion.w,
      sx: obj.scale.x, sy: obj.scale.y, sz: obj.scale.z
    })).filter(a => a.sourceUrl)
  }
  try { localStorage.setItem(pkey, JSON.stringify(config)) } catch {}
  savePlateAssignments()
}

async function restorePlateConfig() {
  if (!props.projectId) return false
  const pkey = `gemslice_plates_project_${props.projectId}`
  try {
    const raw = localStorage.getItem(pkey)
    if (!raw) return false
    const config = JSON.parse(raw)
    if (!config.plates || config.plates.length === 0) return false

    // Set flag immediately (before async model loads) so AssetDetailView
    // doesn't race and add duplicate models via loadOtherAssets()
    plateRestored.value = true

    plates.value = config.plates
    nextPlateId = config.nextPlateId || config.plates.length + 1
    currentPlateId.value = config.activePlateId || config.plates[0].id

    for (const plate of config.plates) {
      const assets = config.plateAssets[plate.id] || []
      const loaded = []
      for (const asset of assets) {
        const group = await loadModelRaw(asset.sourceUrl, asset.fileType, asset.assetId)
        if (group) {
          group.position.set(asset.px, asset.py, asset.pz)
          group.quaternion.set(asset.qx, asset.qy, asset.qz, asset.qw)
          group.scale.set(asset.sx, asset.sy, asset.sz)
          group.updateMatrixWorld(true)
          loaded.push(group)
        }
      }
      if (plate.id === currentPlateId.value) {
        for (const obj of loaded) { scene.add(obj); objects.push(obj) }
      } else {
        plateObjectStore[plate.id] = loaded
      }
    }
    if (objects.length > 0) selectObject(objects[0])
    return true
  } catch (e) {
    console.error('Failed to restore plate config:', e)
    plateRestored.value = false
    return false
  }
}

function loadModelRaw(url, fileType, assetId) {
  if (!url) return Promise.resolve(null)
  const ft = (fileType || '').toLowerCase()
  const group = new THREE.Group()
  if (assetId) group.userData.assetId = assetId
  group.userData.sourceUrl = url
  group.userData.fileType = ft
  return new Promise((resolve) => {
    const onLoaded = () => { centerGizmoOnObject(group); resolve(group) }
    if (ft === '3mf') {
      new ThreeMFLoader().load(url, (loaded) => {
        loaded.traverse(c => { if (c.isMesh) { if (!c.material) c.material = defaultMaterial.clone(); c.castShadow = true } })
        group.add(loaded)
        onLoaded()
      }, undefined, () => resolve(null))
    } else {
      new STLLoader().load(url, (geometry) => {
        geometry.computeVertexNormals()
        const mesh = new THREE.Mesh(geometry, defaultMaterial.clone())
        mesh.castShadow = true
        group.add(mesh)
        onLoaded()
      }, undefined, () => resolve(null))
    }
  })
}

function restoreTransforms() {
  const key = getStorageKey()
  if (!key) return
  try {
    const raw = localStorage.getItem(key)
    if (!raw) return
    const data = JSON.parse(raw)
    for (const obj of objects) {
      const id = obj.userData.assetId
      if (!id || !data[id]) continue
      const t = data[id]
      obj.position.set(t.px, t.py, t.pz)
      obj.quaternion.set(t.qx, t.qy, t.qz, t.qw)
      obj.scale.set(t.sx, t.sy, t.sz)
      obj.updateMatrixWorld(true)
    }
    if (selectedObject) updateDimensions()
  } catch {}
}

// --- Load model (supports adding multiple) ---
const defaultMaterial = new THREE.MeshPhongMaterial({ color: 0x6366f1, specular: 0x444444, shininess: 40 })

function placeOnBed(obj) {
  const w = props.bedWidth
  const d = props.bedDepth
  const box = new THREE.Box3().setFromObject(obj)
  const size = box.getSize(new THREE.Vector3())
  // Center on bed
  obj.position.x += w / 2 - (box.min.x + size.x / 2)
  obj.position.y += -box.min.y
  obj.position.z += d / 2 - (box.min.z + size.z / 2)

  // If multiple objects, offset so they don't overlap
  if (objects.length > 0) {
    const offset = objects.length * 40
    obj.position.x += offset % w < w ? (offset % w) - w/4 : 0
    obj.position.z += Math.floor(offset / w) * 40
  }
}

function centerGizmoOnObject(group) {
  group.updateMatrixWorld(true)
  const box = new THREE.Box3().setFromObject(group)
  const worldCenter = box.getCenter(new THREE.Vector3())
  const offset = worldCenter.clone().sub(group.position)
  const invQuat = group.quaternion.clone().invert()
  const localOffset = offset.clone().applyQuaternion(invQuat)
  localOffset.divide(group.scale)
  group.children.forEach(child => { child.position.sub(localOffset) })
  group.position.copy(worldCenter)
  group.updateMatrixWorld(true)
}

// --- Plate assignment persistence ---
function getPlateAssignKey() {
  return props.projectId ? `gemslice_plate_assign_${props.projectId}` : null
}

function loadPlateAssignments() {
  const key = getPlateAssignKey()
  if (!key) return {}
  try {
    const raw = localStorage.getItem(key)
    return raw ? JSON.parse(raw) : {}
  } catch { return {} }
}

function savePlateAssignments() {
  const key = getPlateAssignKey()
  if (!key) return
  const map = {}
  for (const obj of objects) {
    const id = obj.userData.assetId
    if (id) map[String(id)] = currentPlateId.value
  }
  for (const [plateId, objs] of Object.entries(plateObjectStore)) {
    for (const obj of objs) {
      const id = obj.userData.assetId
      if (id) map[String(id)] = Number(plateId)
    }
  }
  try { localStorage.setItem(key, JSON.stringify(map)) } catch {}
}

function isAssetOnAnyPlate(assetId, sourceUrl) {
  const check = (o) =>
    (assetId && o.userData.assetId && String(o.userData.assetId) === String(assetId)) ||
    (sourceUrl && o.userData.sourceUrl === sourceUrl)
  if (objects.some(check)) return true
  for (const objs of Object.values(plateObjectStore)) {
    if (objs.some(check)) return true
  }
  return false
}

function loadModelFromUrl(url, fileType, assetId = null) {
  if (!scene || !url) return Promise.resolve()

  // Skip if already loaded on any plate
  if (isAssetOnAnyPlate(assetId, url)) return Promise.resolve()

  // Prevent timing-window duplicates: reject if this URL is already being fetched
  const loadKey = assetId ? `id:${assetId}` : `url:${url}`
  if (loadingUrls.has(loadKey)) return Promise.resolve()
  loadingUrls.add(loadKey)

  loadError.value = ""

  const ft = (fileType || "").toLowerCase()
  const group = new THREE.Group()
  if (assetId) group.userData.assetId = assetId
  group.userData.sourceUrl = url
  group.userData.fileType = ft

  return new Promise((resolve) => {
    const onLoaded = () => {
      loadingUrls.delete(loadKey)
      if (unmounted) { resolve(); return }

      centerGizmoOnObject(group)
      placeOnBed(group)

      // Check if this asset belongs to a different plate
      const assignments = loadPlateAssignments()
      const targetPlate = assetId ? assignments[String(assetId)] : null

      if (targetPlate && targetPlate !== currentPlateId.value && plates.value.some(p => p.id === targetPlate)) {
        // Route to the correct plate without adding to current scene
        if (!plateObjectStore[targetPlate]) plateObjectStore[targetPlate] = []
        plateObjectStore[targetPlate].push(group)
      } else {
        scene.add(group)
        objects.push(group)
        selectObject(group)
      }
      savePlateConfig()
      resolve()
    }

    if (ft === "3mf") {
      new ThreeMFLoader().load(url, (loaded) => {
        loaded.traverse((c) => { if (c.isMesh) { if (!c.material) c.material = defaultMaterial.clone(); c.castShadow = true } })
        group.add(loaded)
        onLoaded()
      }, undefined, () => { loadingUrls.delete(loadKey); loadError.value = "Failed to load 3MF"; resolve() })
    } else {
      new STLLoader().load(url, (geometry) => {
        geometry.computeVertexNormals()
        const mesh = new THREE.Mesh(geometry, defaultMaterial.clone())
        mesh.castShadow = true
        group.add(mesh)
        onLoaded()
      }, undefined, () => { loadingUrls.delete(loadKey); loadError.value = "Failed to load STL"; resolve() })
    }
  })
}

function loadModelFromFile(file) {
  loadError.value = ""
  const reader = new FileReader()
  const ext = file.name.split(".").pop().toLowerCase()
  const group = new THREE.Group()

  reader.onload = (e) => {
    const buffer = e.target.result
    try {
      if (ext === "3mf") {
        const loaded = new ThreeMFLoader().parse(buffer)
        loaded.traverse((c) => { if (c.isMesh) { if (!c.material) c.material = defaultMaterial.clone(); c.castShadow = true } })
        group.add(loaded)
      } else {
        const geometry = new STLLoader().parse(buffer)
        geometry.computeVertexNormals()
        group.add(new THREE.Mesh(geometry, defaultMaterial.clone()))
      }
      centerGizmoOnObject(group)
      placeOnBed(group)
      scene.add(group)
      objects.push(group)
      selectObject(group)
      savePlateConfig()
    } catch (err) {
      loadError.value = "Failed to parse file: " + file.name
    }
  }
  reader.readAsArrayBuffer(file)
}

// --- Transform mode ---
function setTransformMode(m) {
  transformMode.value = m
  transformCtrl.setMode(m)
}

// --- Fine adjustment from editable inputs ---
function setPos(axis, event) {
  if (!selectedObject) return
  const val = parseFloat(event.target.value)
  if (isNaN(val)) return
  saveState()
  selectedObject.position[axis] = val
  // Keep on bed
  const box = new THREE.Box3().setFromObject(selectedObject)
  if (box.min.y < 0) selectedObject.position.y -= box.min.y
  updateDimensions()
  saveTransforms()
}

function setRot(axis, event) {
  if (!selectedObject) return
  const deg = parseFloat(event.target.value)
  if (isNaN(deg)) return
  saveState()
  selectedObject.rotation[axis] = THREE.MathUtils.degToRad(deg)
  selectedObject.updateMatrixWorld(true)
  // Drop to bed after rotation
  const box = new THREE.Box3().setFromObject(selectedObject)
  selectedObject.position.y -= box.min.y
  updateDimensions()
  saveTransforms()
}

function setScale(axis, event) {
  if (!selectedObject) return
  const val = parseFloat(event.target.value)
  if (isNaN(val) || val <= 0) return
  saveState()
  selectedObject.scale[axis] = val
  selectedObject.updateMatrixWorld(true)
  const box = new THREE.Box3().setFromObject(selectedObject)
  if (box.min.y < 0) selectedObject.position.y -= box.min.y
  updateDimensions()
  saveTransforms()
}

// --- Auto orient: find optimal print orientation and place flat on bed ---
function autoOrient() {
  if (!selectedObject) return
  let targetMesh = null
  selectedObject.traverse(c => { if (c.isMesh && c.geometry) targetMesh = c })
  if (!targetMesh) return

  const geometry = targetMesh.geometry
  const position = geometry.attributes.position
  if (!position) return

  // Reset rotation to identity first so face normals are in model-local space.
  saveState()
  selectedObject.quaternion.set(0, 0, 0, 1)
  selectedObject.updateMatrixWorld(true)

  const normalMatrix = new THREE.Matrix3().getNormalMatrix(targetMesh.matrixWorld)
  const vA = new THREE.Vector3(), vB = new THREE.Vector3(), vC = new THREE.Vector3()
  const edge1 = new THREE.Vector3(), edge2 = new THREE.Vector3()
  const normal = new THREE.Vector3()
  const index = geometry.index
  const count = index ? index.count / 3 : position.count / 3

  // Collect face data (normals + areas) and build normal buckets
  const faces = []
  const buckets = []
  for (let i = 0; i < count; i++) {
    let a, b, c
    if (index) { a = index.getX(i*3); b = index.getX(i*3+1); c = index.getX(i*3+2) }
    else { a = i*3; b = i*3+1; c = i*3+2 }
    vA.fromBufferAttribute(position, a)
    vB.fromBufferAttribute(position, b)
    vC.fromBufferAttribute(position, c)
    edge1.subVectors(vB, vA)
    edge2.subVectors(vC, vA)
    normal.crossVectors(edge1, edge2)
    const area = normal.length() * 0.5
    if (area < 1e-6) continue
    normal.normalize()
    normal.applyMatrix3(normalMatrix).normalize()
    faces.push({ normal: normal.clone(), area })
    let found = false
    for (const bk of buckets) {
      if (bk.normal.dot(normal) > 0.85) { bk.area += area; found = true; break }
    }
    if (!found) buckets.push({ normal: normal.clone(), area })
  }

  if (buckets.length === 0) return
  buckets.sort((a, b) => b.area - a.area)

  // Build candidates: top 24 buckets + 6 cardinal directions
  const down = new THREE.Vector3(0, -1, 0)
  const candidates = buckets.slice(0, Math.min(24, buckets.length))
  const cardinals = [
    new THREE.Vector3(0, 1, 0), new THREE.Vector3(0, -1, 0),
    new THREE.Vector3(1, 0, 0), new THREE.Vector3(-1, 0, 0),
    new THREE.Vector3(0, 0, 1), new THREE.Vector3(0, 0, -1)
  ]
  for (const dir of cardinals) {
    if (!candidates.some(bk => bk.normal.dot(dir) > 0.85)) {
      candidates.push({ normal: dir.clone(), area: 0 })
    }
  }

  // Score = overhangs / (1 + largestFlatBase)
  // A large flat base (like feet soles) dramatically lowers the score.
  // This ensures models sit on their flattest surface, not just the orientation
  // with fewest overhangs (which would make figurines lie on their backs).
  const totalArea = faces.reduce((s, f) => s + f.area, 0)
  const scored = []

  for (const bk of candidates) {
    const rot = new THREE.Quaternion().setFromUnitVectors(bk.normal, down)
    let overhangArea = 0

    // Find the largest single TRULY FLAT region that would touch the bed.
    // Threshold 0.99 (~8°) ensures only genuinely flat surfaces count —
    // curved surfaces (backs, heads) won't merge into one big bucket.
    const bedBuckets = []
    for (const f of faces) {
      const rotNormal = f.normal.clone().applyQuaternion(rot)
      const ry = rotNormal.y
      if (ry < -0.707) overhangArea += f.area // faces > 45° from horizontal

      if (ry < -0.85) { // faces flat enough to be bed contact
        let matched = false
        for (const bb of bedBuckets) {
          if (bb.normal.dot(rotNormal) > 0.99) { // ~8° — only truly coplanar faces
            bb.area += f.area
            matched = true
            break
          }
        }
        if (!matched) bedBuckets.push({ normal: rotNormal.clone(), area: f.area })
      }
    }

    const largestFlatBase = bedBuckets.length > 0
      ? Math.max(...bedBuckets.map(b => b.area))
      : 0
    const hasContact = largestFlatBase > totalArea * 0.0005

    // Ratio: fewer overhangs AND bigger flat base = lower score = better
    const score = hasContact
      ? (overhangArea + 1) / (largestFlatBase + 1)
      : totalArea * 100
    scored.push({ bucket: bk, score, hasContact })
  }

  scored.sort((a, b) => a.score - b.score)
  const chosen = scored.find(s => s.hasContact) || scored[0]

  // Apply the winning rotation, then snap all Euler angles to nearest 90°
  const quat = new THREE.Quaternion().setFromUnitVectors(chosen.bucket.normal, down)
  selectedObject.quaternion.copy(quat)
  const euler = new THREE.Euler().setFromQuaternion(quat)
  const snap90 = (v) => Math.round(v / (Math.PI / 2)) * (Math.PI / 2)
  euler.x = snap90(euler.x); euler.y = snap90(euler.y); euler.z = snap90(euler.z)
  selectedObject.quaternion.setFromEuler(euler)
  selectedObject.updateMatrixWorld(true)

  centerGizmoOnObject(selectedObject)

  // Drop to bed — ensure bounding box bottom is at y=0, retry until flat
  dropToBed(selectedObject)
  for (let i = 0; i < 3; i++) {
    selectedObject.updateMatrixWorld(true)
    const checkBox = new THREE.Box3().setFromObject(selectedObject)
    if (Math.abs(checkBox.min.y) <= 0.01) break
    dropToBed(selectedObject)
  }

  // Center on bed X/Z
  selectedObject.updateMatrixWorld(true)
  const box = new THREE.Box3().setFromObject(selectedObject)
  const center = box.getCenter(new THREE.Vector3())
  const w = props.bedWidth, d = props.bedDepth
  selectedObject.position.x += w / 2 - center.x
  selectedObject.position.z += d / 2 - center.z

  updateDimensions()
  saveTransforms()
}

// Ensure object sits flat on the build plate (y=0)
function dropToBed(obj) {
  obj.updateMatrixWorld(true)
  const box = new THREE.Box3().setFromObject(obj)
  obj.position.y -= box.min.y // move so bottom touches y=0
  obj.updateMatrixWorld(true)
  // Verify — if still floating (due to numerical issues), force it
  const check = new THREE.Box3().setFromObject(obj)
  if (Math.abs(check.min.y) > 0.01) {
    obj.position.y -= check.min.y
    obj.updateMatrixWorld(true)
  }
}

// --- Delete selected ---
function deleteSelected() {
  if (!selectedObject) return
  saveState()
  const deletedAssetId = selectedObject.userData.assetId || null
  transformCtrl.detach()
  scene.remove(selectedObject)
  const idx = objects.indexOf(selectedObject)
  if (idx >= 0) objects.splice(idx, 1)
  selectedObject = null
  modelDims.value = null
  saveTransforms()
  if (deletedAssetId) emit('asset-deleted', deletedAssetId)
}

// --- Clipboard (copy / cut / paste) ---
let clipboard = null

function copySelected() {
  if (!selectedObject) return
  clipboard = selectedObject
}

function cutSelected() {
  if (!selectedObject) return
  copySelected()
  deleteSelected()
}

function pasteClipboard() {
  if (!clipboard) return
  saveState()
  const clone = clipboard.clone()
  clone.userData = { ...clipboard.userData }
  // Offset so the paste doesn't overlap the original
  clone.position.x += 20
  clone.position.z += 20
  const box = new THREE.Box3().setFromObject(clone)
  if (box.min.y < 0) clone.position.y -= box.min.y
  scene.add(clone)
  objects.push(clone)
  selectObject(clone)
  saveTransforms()
}

// --- View presets ---
function resetView() {
  const w = props.bedWidth, d = props.bedDepth
  camera.position.set(w * 0.7, w * 0.5, w * 0.9)
  controls.target.set(w / 2, 0, d / 2)
  controls.update()
}
function viewTop() {
  const w = props.bedWidth, d = props.bedDepth
  camera.position.set(w / 2, w * 1.5, d / 2)
  controls.target.set(w / 2, 0, d / 2)
  controls.update()
}
function viewFront() {
  const w = props.bedWidth, d = props.bedDepth
  camera.position.set(w / 2, w * 0.3, d * 1.5)
  controls.target.set(w / 2, w * 0.1, d / 2)
  controls.update()
}
function viewRight() {
  const w = props.bedWidth, d = props.bedDepth
  camera.position.set(w * 1.5, w * 0.3, d / 2)
  controls.target.set(w / 2, w * 0.1, d / 2)
  controls.update()
}

// --- Drag and drop ---
function onDragOver(e) { e.preventDefault(); dragging.value = true }
function onDragLeave() { dragging.value = false }
function onDrop(e) {
  e.preventDefault()
  dragging.value = false
  const files = Array.from(e.dataTransfer.files).filter(f => /\.(stl|3mf)$/i.test(f.name))
  for (const file of files) {
    loadModelFromFile(file)
    emit("file-dropped", file)
  }
}

// --- Resize ---
function handleResize() {
  const el = container.value
  if (!el || !renderer || el.clientWidth === 0 || el.clientHeight === 0) return
  camera.aspect = el.clientWidth / el.clientHeight
  camera.updateProjectionMatrix()
  renderer.setSize(el.clientWidth, el.clientHeight)
}

function onKeyDown(e) {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return
  if (e.ctrlKey || e.metaKey) {
    if (e.key === 'z') { e.preventDefault(); undo() }
    else if (e.key === 'y') { e.preventDefault(); redo() }
    else if (e.key === 'c') { e.preventDefault(); copySelected() }
    else if (e.key === 'x') { e.preventDefault(); cutSelected() }
    else if (e.key === 'v') { e.preventDefault(); pasteClipboard() }
  }
  if (e.key === 'Delete' || e.key === 'Backspace') {
    if (e.target.tagName !== 'INPUT') deleteSelected()
  }
}

onMounted(async () => {
  init()
  const restored = await restorePlateConfig()
  if (!restored && props.url) {
    await loadModelFromUrl(props.url, props.fileType, props.assetId)
  }
  resizeObs = new ResizeObserver(() => handleResize())
  if (container.value) resizeObs.observe(container.value)
  window.addEventListener("keydown", onKeyDown)
})

onUnmounted(() => {
  unmounted = true
  resizeObs?.disconnect()
  window.removeEventListener("keydown", onKeyDown)
  renderer?.domElement?.removeEventListener("pointerdown", onPointerDown)
  cancelAnimationFrame(animationId)
  transformCtrl?.dispose()
  renderer?.dispose()
  controls?.dispose()
})

watch(() => props.url, (u) => {
  if (!u) return
  // loadModelFromUrl already has duplicate + plate-assignment checks
  loadModelFromUrl(u, props.fileType, props.assetId)
})

watch(() => [props.bedWidth, props.bedDepth], ([w, d]) => {
  if (scene) rebuildBed(w, d)
})

// --- Multi-plate management ---
function switchToPlate(plateId) {
  if (plateId === currentPlateId.value) return
  // Deselect
  transformCtrl.detach()
  selectedObject = null
  modelDims.value = null
  // Save current plate's objects
  plateObjectStore[currentPlateId.value] = [...objects]
  // Remove current objects from scene
  for (const obj of objects) scene.remove(obj)
  objects.length = 0
  // Load new plate's objects
  const plateObjs = plateObjectStore[plateId] || []
  for (const obj of plateObjs) {
    scene.add(obj)
    objects.push(obj)
  }
  currentPlateId.value = plateId
  savePlateConfig()
}

function addPlate() {
  const id = nextPlateId++
  plates.value.push({ id, name: `Plate ${id}` })
  switchToPlate(id)
}

function removePlate(plateId) {
  if (plates.value.length <= 1) return
  // Remove objects from this plate
  const objs = plateObjectStore[plateId] || []
  if (plateId === currentPlateId.value) {
    for (const obj of objects) scene.remove(obj)
    objects.length = 0
  }
  for (const obj of objs) {
    if (obj.geometry) obj.geometry.dispose()
  }
  delete plateObjectStore[plateId]
  plates.value = plates.value.filter(p => p.id !== plateId)
  // Switch to first remaining plate if we removed the active one
  if (plateId === currentPlateId.value) {
    switchToPlate(plates.value[0].id)
  }
  savePlateConfig()
}

// Export all objects on the bed as a single binary STL for the slicer.
// Converts Three.js Y-up to Slicer Z-up via Y↔Z swap.
function exportSceneAsSTL() {
  const tempScene = new THREE.Scene()
  for (const obj of objects) {
    obj.updateMatrixWorld(true)
    obj.traverse(c => {
      if (c.isMesh && c.geometry) {
        const geo = c.geometry.clone()
        geo.applyMatrix4(c.matrixWorld)
        const pos = geo.attributes.position
        for (let i = 0; i < pos.count; i++) {
          const y = pos.getY(i) // Three.js Y = up (height)
          const z = pos.getZ(i) // Three.js Z = depth
          pos.setY(i, z)  // Three Z -> Slicer Y
          pos.setZ(i, y)  // Three Y -> Slicer Z (height)
        }
        pos.needsUpdate = true
        geo.computeVertexNormals()
        tempScene.add(new THREE.Mesh(geo))
      }
    })
  }
  const exporter = new STLExporter()
  const buffer = exporter.parse(tempScene, { binary: true })
  return new Blob([buffer], { type: 'application/octet-stream' })
}

function getCameraState() {
  if (!camera || !controls) return null
  return {
    px: camera.position.x, py: camera.position.y, pz: camera.position.z,
    tx: controls.target.x, ty: controls.target.y, tz: controls.target.z
  }
}

defineExpose({ loadModelFromUrl, restoreTransforms, exportSceneAsSTL, getCameraState, currentPlateId, plates, plateRestored })
</script>

<template>
  <div
    class="flex flex-col h-full bg-[#2a2a2a] relative"
    @dragover="onDragOver"
    @dragleave="onDragLeave"
    @drop="onDrop"
  >
    <!-- Drop overlay -->
    <div v-if="dragging" class="absolute inset-0 z-10 bg-indigo-900/40 border-2 border-dashed border-indigo-400 rounded flex items-center justify-center pointer-events-none">
      <span class="text-white text-lg font-medium">Drop STL / 3MF files here</span>
    </div>

    <!-- Toolbar -->
    <div class="flex items-center justify-between px-3 py-2 bg-[#333] border-b border-gray-700 text-xs shrink-0">
      <div class="flex items-center gap-1">
        <button v-for="m in ['translate','rotate','scale']" :key="m" @click="setTransformMode(m)"
          :class="['px-3 py-1.5 rounded cursor-pointer', transformMode === m ? 'bg-indigo-600 text-white' : 'bg-gray-600 text-gray-300 hover:bg-gray-500']"
        >{{ m === 'translate' ? 'Move' : m === 'rotate' ? 'Rotate' : 'Scale' }}</button>
        <span class="mx-1 text-gray-600">|</span>
        <button @click="autoOrient" class="px-3 py-1.5 rounded bg-gray-600 text-gray-300 hover:bg-gray-500 cursor-pointer" title="Auto Orient">Auto-Orient</button>
        <button @click="deleteSelected" class="px-3 py-1.5 rounded bg-gray-600 text-red-400 hover:bg-gray-500 cursor-pointer" title="Delete selected">Delete</button>
      </div>
      <div class="flex items-center gap-1">
        <button v-for="v in [{l:'Front',f:viewFront},{l:'Top',f:viewTop},{l:'Right',f:viewRight},{l:'Reset',f:resetView}]" :key="v.l"
          @click="v.f" class="px-2 py-1.5 rounded bg-gray-600 text-gray-300 hover:bg-gray-500 cursor-pointer"
        >{{ v.l }}</button>
      </div>
    </div>

    <!-- 3D canvas -->
    <div ref="container" class="flex-1 min-h-0"></div>

    <!-- Plate tabs -->
    <div class="flex items-center gap-1 px-2 py-1.5 bg-[#2f2f2f] border-t border-gray-700 text-xs shrink-0">
      <button v-for="plate in plates" :key="plate.id"
        @click="switchToPlate(plate.id)"
        :class="['group flex items-center gap-1 px-3 py-1 rounded cursor-pointer transition-colors', currentPlateId === plate.id ? 'bg-indigo-600 text-white' : 'bg-gray-600 text-gray-300 hover:bg-gray-500']"
      >
        {{ plate.name }}
        <span v-if="plates.length > 1" @click.stop="removePlate(plate.id)" class="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-red-400 ml-0.5">&times;</span>
      </button>
      <button @click="addPlate" class="px-2 py-1 rounded bg-gray-700 text-gray-400 hover:bg-gray-600 hover:text-gray-200 cursor-pointer" title="Add Plate">+</button>
    </div>

    <!-- Dimension & Transform bar -->
    <div class="flex items-center gap-2 px-3 py-2 bg-[#333] border-t border-gray-700 text-xs text-gray-300 shrink-0">
      <template v-if="modelDims">
        <span class="text-gray-500">Size</span>
        <span><span class="text-red-400 font-medium">X:</span> {{ modelDims.x }}</span>
        <span><span class="text-green-400 font-medium">Y:</span> {{ modelDims.y }}</span>
        <span><span class="text-blue-400 font-medium">Z:</span> {{ modelDims.z }} mm</span>
        <span class="text-gray-600">|</span>
        <template v-if="transformMode === 'translate'">
          <span class="text-gray-500">Pos</span>
          <label class="text-red-400">X</label><input type="number" :value="modelDims.px" step="1" @change="setPos('x', $event)" class="w-14 bg-[#444] border border-gray-600 rounded px-1 py-0.5 text-center text-xs" />
          <label class="text-green-400">Y</label><input type="number" :value="modelDims.py" step="1" @change="setPos('y', $event)" class="w-14 bg-[#444] border border-gray-600 rounded px-1 py-0.5 text-center text-xs" />
          <label class="text-blue-400">Z</label><input type="number" :value="modelDims.pz" step="1" @change="setPos('z', $event)" class="w-14 bg-[#444] border border-gray-600 rounded px-1 py-0.5 text-center text-xs" />
        </template>
        <template v-else-if="transformMode === 'rotate'">
          <span class="text-gray-500">Rot</span>
          <label class="text-red-400">X</label><input type="number" :value="modelDims.rx" step="5" @change="setRot('x', $event)" class="w-14 bg-[#444] border border-gray-600 rounded px-1 py-0.5 text-center text-xs" />&deg;
          <label class="text-green-400">Y</label><input type="number" :value="modelDims.ry" step="5" @change="setRot('y', $event)" class="w-14 bg-[#444] border border-gray-600 rounded px-1 py-0.5 text-center text-xs" />&deg;
          <label class="text-blue-400">Z</label><input type="number" :value="modelDims.rz" step="5" @change="setRot('z', $event)" class="w-14 bg-[#444] border border-gray-600 rounded px-1 py-0.5 text-center text-xs" />&deg;
        </template>
        <template v-else>
          <span class="text-gray-500">Scale</span>
          <label class="text-red-400">X</label><input type="number" :value="modelDims.sx" step="0.1" min="0.01" @change="setScale('x', $event)" class="w-14 bg-[#444] border border-gray-600 rounded px-1 py-0.5 text-center text-xs" />
          <label class="text-green-400">Y</label><input type="number" :value="modelDims.sy" step="0.1" min="0.01" @change="setScale('y', $event)" class="w-14 bg-[#444] border border-gray-600 rounded px-1 py-0.5 text-center text-xs" />
          <label class="text-blue-400">Z</label><input type="number" :value="modelDims.sz" step="0.1" min="0.01" @change="setScale('z', $event)" class="w-14 bg-[#444] border border-gray-600 rounded px-1 py-0.5 text-center text-xs" />
        </template>
      </template>
      <span v-else class="text-gray-500">Drag files onto the build plate or click an object to select</span>
      <span class="text-gray-500 ml-auto">{{ objects.length }} object{{ objects.length !== 1 ? 's' : '' }} | Bed: {{ bedWidth }}&times;{{ bedDepth }} mm</span>
    </div>

    <p v-if="loadError" class="absolute bottom-10 left-3 text-red-500 text-sm bg-[#333] px-2 py-1 rounded">{{ loadError }}</p>
  </div>
</template>
