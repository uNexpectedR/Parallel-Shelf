proc swarmWorkDir(topic: string): string =
  var dir = context().instancePersistencePath
  if dir.len == 0: dir = getEnv("MUSTER_DATA_DIR", getTempDir() / "muster")
  dir / "fileshare" / toHex(sha256(topic.toOpenArrayByte(0, topic.high)))[0 ..< 16].toLowerAscii

proc swarmNode(topic: string): SwarmNode =
  if topic notin gSwarmNodes:
    gSwarmNodes[topic] = newSwarmNode(storage(), moduleKeystore(), swarmWorkDir(topic),
                                      proc(): int64 = int64(epochTime()))
  gSwarmNodes[topic]

proc fileShareReadiness(): FileShareReadiness =
  ## Where storage_module stands: the host's registry first (installed? running?), and the
  ## node only once the host says it is ready or cannot say (storage_readiness.nim).
  fileShareReadiness(moduleFacts().moduleRecord(StoragePackage), proc(): NodeStatus = storage().status())

proc fileShareReady(): (bool, string) =
  let r = fileShareReadiness()
  (r.ready, r.note)

proc fileSharePump() =
  ## Finish what the storage node has done since the last tick, room by room.
  if gStorage == nil or not fileShareReadiness().ready: return
  for topic, node in gSwarmNodes:
    if topic in gSessions:
      try: node.pump(gSessions[topic])
      except CatchableError: discard

proc musterFileshareStatus(): string =
  let rd = fileShareReadiness()
  var node = newJObject()
  if rd.ready:
    let r = storage().reach()
    node = %*{"peerId": r.peerId, "addrs": r.addrs, "network": r.network, "spr": storage().spr()}
  $(%*{"ready": rd.ready, "state": $rd.state, "note": rd.note, "install": rd.install, "node": node})

proc musterFileshareShare(path: string): string =
  if gSession == nil: return $(%*{"error": "not-joined"})
  let (ready, note) = fileShareReady()
  if not ready: return $(%*{"error": "not-ready", "detail": note})
  if not path.isAbsolute or not fileExists(path):
    return $(%*{"error": "no such file", "detail": path})
  let mime = (let e = splitFile(path).ext; if e.len > 1: newMimetypes().getMimetype(e[1 .. ^1]) else: "application/octet-stream")
  let op = swarmNode(gTopic).share(gSession, path, mime)
  for o in swarmNode(gTopic).ops():
    if o.id == op and o.state == opFailed: return $(%*{"error": o.error})
  $(%*{"op": op})

proc musterFileshareFiles(): string =
  if gSession == nil: return $(%*{"ready": false, "state": "not-joined", "note": "not-joined", "files": [], "ops": []})
  gSession.poll()
  fileSharePump()
  let rd = fileShareReadiness()
  let (ready, note) = (rd.ready, rd.note)
  let me = toHex(gSession.selfIdentity().toBytes()).toLowerAscii
  var files = newJArray()
  for f in reduceSwarm(gSession.roomEvents()):
    var seeders = newJArray()
    var seeding = false
    for sd in f.seeders:
      if sd.member == me: seeding = true
      seeders.add %*{"member": sd.member, "alias": contactBook().aliasOf(sd.member), "self": sd.member == me}
    files.add %*{"id": f.fid, "name": f.name, "mime": f.mime, "size": int64(f.size),
                 "sharer": f.sharer, "sharerAlias": contactBook().aliasOf(f.sharer),
                 "self": f.sharer == me, "retracted": f.retracted, "seeders": seeders,
                 "seeding": seeding, "held": ready and storage().has(f.cid)}
  var ops = newJArray()
  if gTopic in gSwarmNodes:
    for o in gSwarmNodes[gTopic].ops():
      ops.add %*{"id": o.id, "kind": $o.kind, "state": $o.state, "error": o.error, "file": o.fid,
                 "name": o.name, "bytes": int64(o.bytes), "total": int64(o.total),
                 "dest": o.dest, "private": o.private}
  $(%*{"ready": ready, "state": $rd.state, "note": note, "install": rd.install, "files": files, "ops": ops})

proc musterFileshareFetch(fileId, folder, privately: string): string =
  if gSession == nil: return $(%*{"error": "not-joined"})
  let (ready, note) = fileShareReady()
  if not ready: return $(%*{"error": "not-ready", "detail": note})
  # the UI resolves an empty folder to the person's own Downloads; this is the fallback for
  # a host that does not, and a folder that cannot be made says why instead of raising
  var dir = folder.strip()
  if dir.len == 0: dir = getHomeDir() / "Downloads"
  try: createDir(dir)
  except OSError as e: return $(%*{"error": "cannot use the folder " & dir & ": " & e.msg})
  let node = swarmNode(gTopic)
  let op = node.fetch(gSession, fileId, dir, private = privately == "true")
  for o in node.ops():
    if o.id == op and o.state == opFailed: return $(%*{"error": o.error})
  $(%*{"op": op})

proc musterFileshareSeed(fileId, on: 