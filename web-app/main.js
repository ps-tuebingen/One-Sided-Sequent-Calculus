class WASI {
    constructor(wasiConfig) {
        this.lastStdin = 0;
        this.env = {};
        this.sleep = wasiConfig.sleep;
        this.getStdin = wasiConfig.getStdin;
        this.sendStdout = wasiConfig.sendStdout;
        this.sendStderr = wasiConfig.sendStderr;
        // Destructure our wasiConfig
        let preopens = {};
        if (wasiConfig.preopens) {
            preopens = wasiConfig.preopens;
        }
        if (wasiConfig && wasiConfig.env) {
            this.env = wasiConfig.env;
        }
        let args = [];
        if (wasiConfig && wasiConfig.args) {
            args = wasiConfig.args;
        }
        // @ts-ignore
        this.memory = undefined;
        // @ts-ignore
        this.view = undefined;
        this.bindings = wasiConfig.bindings;
        const fs = this.bindings.fs;
        this.FD_MAP = new Map([
            [
                constants_1.WASI_STDIN_FILENO,
                {
                    real: 0,
                    filetype: constants_1.WASI_FILETYPE_CHARACTER_DEVICE,
                    // offset: BigInt(0),
                    rights: {
                        base: STDIN_DEFAULT_RIGHTS,
                        inheriting: BigInt(0),
                    },
                    path: "/dev/stdin",
                },
            ],
            [
                constants_1.WASI_STDOUT_FILENO,
                {
                    real: 1,
                    filetype: constants_1.WASI_FILETYPE_CHARACTER_DEVICE,
                    // offset: BigInt(0),
                    rights: {
                        base: STDOUT_DEFAULT_RIGHTS,
                        inheriting: BigInt(0),
                    },
                    path: "/dev/stdout",
                },
            ],
            [
                constants_1.WASI_STDERR_FILENO,
                {
                    real: 2,
                    filetype: constants_1.WASI_FILETYPE_CHARACTER_DEVICE,
                    // offset: BigInt(0),
                    rights: {
                        base: STDERR_DEFAULT_RIGHTS,
                        inheriting: BigInt(0),
                    },
                    path: "/dev/stderr",
                },
            ],
        ]);
        const path = this.bindings.path;
        for (const [k, v] of Object.entries(preopens)) {
            const real = fs.openSync(v, fs.constants.O_RDONLY);
            const newfd = this.getUnusedFileDescriptor();
            this.FD_MAP.set(newfd, {
                real,
                filetype: constants_1.WASI_FILETYPE_DIRECTORY,
                // offset: BigInt(0),
                rights: {
                    base: constants_1.RIGHTS_DIRECTORY_BASE,
                    inheriting: constants_1.RIGHTS_DIRECTORY_INHERITING,
                },
                fakePath: k,
                path: v,
            });
        }
        const getiovs = (iovs, iovsLen) => {
            // iovs* -> [iov, iov, ...]
            // __wasi_ciovec_t {
            //   void* buf,
            //   size_t buf_len,
            // }
            this.refreshMemory();
            const buffers = Array.from({ length: iovsLen }, (_, i) => {
                const ptr = iovs + i * 8;
                const buf = this.view.getUint32(ptr, true);
                let bufLen = this.view.getUint32(ptr + 4, true);
                // the mmap stuff in wasi tries to make this overwrite all
                // allocated memory, so we cap it or things crash.
                // TODO: maybe we need to allocate more memory?  I don't know!!
                if (bufLen > this.memory.buffer.byteLength - buf) {
                    //           console.log({
                    //             buf,
                    //             bufLen,
                    //             total_memory: this.memory.buffer.byteLength,
                    //           });
                    log("getiovs: warning -- truncating buffer to fit in memory");
                    bufLen = Math.min(bufLen, Math.max(0, this.memory.buffer.byteLength - buf));
                }
                try {
                    const buffer = new Uint8Array(this.memory.buffer, buf, bufLen);
                    return (0, typedarray_to_buffer_1.default)(buffer);
                }
                catch (err) {
                    // don't hide this
                    console.warn("WASI.getiovs -- invalid buffer", err);
                    // but at least make it so we don't totally kill WASM, so we
                    // get a traceback in the calling program (say python).
                    // TODO: Right now this sort of thing happens with aggressive use of mmap,
                    // but I plan to replace how mmap works with something that is viable.
                    throw new types_1.WASIError(constants_1.WASI_EINVAL);
                }
            });
            return buffers;
        };
        const CHECK_FD = (fd, rights) => {
            // log("CHECK_FD", { fd, rights });
            const stats = stat(this, fd);
            // log("CHECK_FD", { stats });
            if (rights !== BigInt(0) && (stats.rights.base & rights) === BigInt(0)) {
                throw new types_1.WASIError(constants_1.WASI_EPERM);
            }
            return stats;
        };
        const CPUTIME_START = this.bindings.hrtime();
        const now = (clockId) => {
            switch (clockId) {
                case constants_1.WASI_CLOCK_MONOTONIC:
                    return this.bindings.hrtime();
                case constants_1.WASI_CLOCK_REALTIME:
                    return msToNs(Date.now());
                case constants_1.WASI_CLOCK_PROCESS_CPUTIME_ID:
                case constants_1.WASI_CLOCK_THREAD_CPUTIME_ID: // TODO -- this assumes 1 thread
                    return this.bindings.hrtime() - CPUTIME_START;
                default:
                    return null;
            }
        };
        this.wasiImport = {
            args_get: (argv, argvBuf) => {
                this.refreshMemory();
                let coffset = argv;
                let offset = argvBuf;
                args.forEach((a) => {
                    this.view.setUint32(coffset, offset, true);
                    coffset += 4;
                    offset += Buffer.from(this.memory.buffer).write(`${a}\0`, offset);
                });
                return constants_1.WASI_ESUCCESS;
            },
            args_sizes_get: (argc, argvBufSize) => {
                this.refreshMemory();
                this.view.setUint32(argc, args.length, true);
                const size = args.reduce((acc, a) => acc + Buffer.byteLength(a) + 1, 0);
                this.view.setUint32(argvBufSize, size, true);
                return constants_1.WASI_ESUCCESS;
            },
            environ_get: (environ, environBuf) => {
                this.refreshMemory();
                let coffset = environ;
                let offset = environBuf;
                Object.entries(this.env).forEach(([key, value]) => {
                    this.view.setUint32(coffset, offset, true);
                    coffset += 4;
                    offset += Buffer.from(this.memory.buffer).write(`${key}=${value}\0`, offset);
                });
                return constants_1.WASI_ESUCCESS;
            },
            environ_sizes_get: (environCount, environBufSize) => {
                this.refreshMemory();
                const envProcessed = Object.entries(this.env).map(([key, value]) => `${key}=${value}\0`);
                const size = envProcessed.reduce((acc, e) => acc + Buffer.byteLength(e), 0);
                this.view.setUint32(environCount, envProcessed.length, true);
                this.view.setUint32(environBufSize, size, true);
                return constants_1.WASI_ESUCCESS;
            },
            clock_res_get: (clockId, resolution) => {
                let res;
                switch (clockId) {
                    case constants_1.WASI_CLOCK_MONOTONIC:
                    case constants_1.WASI_CLOCK_PROCESS_CPUTIME_ID:
                    case constants_1.WASI_CLOCK_THREAD_CPUTIME_ID: {
                        res = BigInt(1);
                        break;
                    }
                    case constants_1.WASI_CLOCK_REALTIME: {
                        res = BigInt(1000);
                        break;
                    }
                }
                if (!res) {
                    throw Error("invalid clockId");
                }
                this.view.setBigUint64(resolution, res);
                return constants_1.WASI_ESUCCESS;
            },
            clock_time_get: (clockId, _precision, time) => {
                this.refreshMemory();
                const n = now(clockId);
                if (n === null) {
                    return constants_1.WASI_EINVAL;
                }
                this.view.setBigUint64(time, BigInt(n), true);
                return constants_1.WASI_ESUCCESS;
            },
            fd_advise: wrap((fd, _offset, _len, _advice) => {
                CHECK_FD(fd, constants_1.WASI_RIGHT_FD_ADVISE);
                return constants_1.WASI_ENOSYS;
            }),
            fd_allocate: wrap((fd, _offset, _len) => {
                CHECK_FD(fd, constants_1.WASI_RIGHT_FD_ALLOCATE);
                return constants_1.WASI_ENOSYS;
            }),
            fd_close: wrap((fd) => {
                const stats = CHECK_FD(fd, BigInt(0));
                fs.closeSync(stats.real);
                this.FD_MAP.delete(fd);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_datasync: wrap((fd) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_DATASYNC);
                fs.fdatasyncSync(stats.real);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_fdstat_get: wrap((fd, bufPtr) => {
                const stats = CHECK_FD(fd, BigInt(0));
                // console.log("fd_fdstat_get", fd, stats);
                this.refreshMemory();
                if (stats.filetype == null) {
                    throw Error("stats.filetype must be set");
                }
                this.view.setUint8(bufPtr, stats.filetype); // FILETYPE u8
                this.view.setUint16(bufPtr + 2, 0, true); // FDFLAG u16
                this.view.setUint16(bufPtr + 4, 0, true); // FDFLAG u16
                this.view.setBigUint64(bufPtr + 8, BigInt(stats.rights.base), true); // u64
                this.view.setBigUint64(bufPtr + 8 + 8, BigInt(stats.rights.inheriting), true); // u64
                return constants_1.WASI_ESUCCESS;
            }),
            /*
            fd_fdstat_set_flags
      
            Docs From upstream:
            Adjust the flags associated with a file descriptor.
            Note: This is similar to `fcntl(fd, F_SETFL, flags)` in POSIX.
      
            This could be supported via posix-node in general (when available)
            for sockets and stdin/stdout/stderr and genuine files (but not
            for memfs, obviously).  It's typically used by C programs for
            locking files, but most importantly for us, for setting whether
            reading from a fd is nonblocking (very important for stdin)
            or should time out after a certain amount of time (e.g., very
            important for a network socket).
      
            For now we implement this in a very small number of cases
            and return "Function not implemented" otherwise.
            */
            fd_fdstat_set_flags: wrap((fd, flags) => {
                // Are we allowed to set flags.  This more means: "is it implemented?".
                // Right now we only set this flag for sockets (that's done in the
                // external kernel module in src/wasm/posix/socket.ts).
                CHECK_FD(fd, constants_1.WASI_RIGHT_FD_FDSTAT_SET_FLAGS);
                if (this.wasiImport.sock_fcntlSetFlags(fd, flags) == 0) {
                    return constants_1.WASI_ESUCCESS;
                }
                return constants_1.WASI_ENOSYS;
            }),
            fd_fdstat_set_rights: wrap((fd, fsRightsBase, fsRightsInheriting) => {
                const stats = CHECK_FD(fd, BigInt(0));
                const nrb = stats.rights.base | fsRightsBase;
                if (nrb > stats.rights.base) {
                    return constants_1.WASI_EPERM;
                }
                const nri = stats.rights.inheriting | fsRightsInheriting;
                if (nri > stats.rights.inheriting) {
                    return constants_1.WASI_EPERM;
                }
                stats.rights.base = fsRightsBase;
                stats.rights.inheriting = fsRightsInheriting;
                return constants_1.WASI_ESUCCESS;
            }),
            fd_filestat_get: wrap((fd, bufPtr) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_FILESTAT_GET);
                const rstats = this.fstatSync(stats.real);
                this.refreshMemory();
                this.view.setBigUint64(bufPtr, BigInt(rstats.dev), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, BigInt(rstats.ino), true);
                bufPtr += 8;
                if (stats.filetype == null) {
                    throw Error("stats.filetype must be set");
                }
                this.view.setUint8(bufPtr, stats.filetype);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, BigInt(rstats.nlink), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, BigInt(rstats.size), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, msToNs(rstats.atimeMs), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, msToNs(rstats.mtimeMs), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, msToNs(rstats.ctimeMs), true);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_filestat_set_size: wrap((fd, stSize) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_FILESTAT_SET_SIZE);
                fs.ftruncateSync(stats.real, Number(stSize));
                return constants_1.WASI_ESUCCESS;
            }),
            fd_filestat_set_times: wrap((fd, stAtim, stMtim, fstflags) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_FILESTAT_SET_TIMES);
                const rstats = this.fstatSync(stats.real);
                let atim = rstats.atime;
                let mtim = rstats.mtime;
                const n = nsToMs(now(constants_1.WASI_CLOCK_REALTIME));
                const atimflags = constants_1.WASI_FILESTAT_SET_ATIM | constants_1.WASI_FILESTAT_SET_ATIM_NOW;
                if ((fstflags & atimflags) === atimflags) {
                    return constants_1.WASI_EINVAL;
                }
                const mtimflags = constants_1.WASI_FILESTAT_SET_MTIM | constants_1.WASI_FILESTAT_SET_MTIM_NOW;
                if ((fstflags & mtimflags) === mtimflags) {
                    return constants_1.WASI_EINVAL;
                }
                if ((fstflags & constants_1.WASI_FILESTAT_SET_ATIM) === constants_1.WASI_FILESTAT_SET_ATIM) {
                    atim = nsToMs(stAtim);
                }
                else if ((fstflags & constants_1.WASI_FILESTAT_SET_ATIM_NOW) ===
                    constants_1.WASI_FILESTAT_SET_ATIM_NOW) {
                    atim = n;
                }
                if ((fstflags & constants_1.WASI_FILESTAT_SET_MTIM) === constants_1.WASI_FILESTAT_SET_MTIM) {
                    mtim = nsToMs(stMtim);
                }
                else if ((fstflags & constants_1.WASI_FILESTAT_SET_MTIM_NOW) ===
                    constants_1.WASI_FILESTAT_SET_MTIM_NOW) {
                    mtim = n;
                }
                fs.futimesSync(stats.real, new Date(atim), new Date(mtim));
                return constants_1.WASI_ESUCCESS;
            }),
            fd_prestat_get: wrap((fd, bufPtr) => {
                const stats = CHECK_FD(fd, BigInt(0));
                // log("fd_prestat_get", { fd, stats });
                this.refreshMemory();
                this.view.setUint8(bufPtr, constants_1.WASI_PREOPENTYPE_DIR);
                this.view.setUint32(bufPtr + 4, 
                // TODO: this is definitely completely wrong unless preopens=/.
                // NOTE: when both paths are blank, we return "".  This is used by
                // cPython on sockets.   It used to raise an error here.
                Buffer.byteLength(stats.fakePath ?? stats.path ?? ""), true);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_prestat_dir_name: wrap((fd, pathPtr, pathLen) => {
                const stats = CHECK_FD(fd, BigInt(0));
                this.refreshMemory();
                // NOTE: when both paths are blank, we return "".  This is used by
                // cPython on sockets.  It used to raise an error here.
                Buffer.from(this.memory.buffer).write(stats.fakePath ?? stats.path ?? "" /* TODO: wrong in general!? */, pathPtr, pathLen, "utf8");
                return constants_1.WASI_ESUCCESS;
            }),
            fd_pwrite: wrap((fd, iovs, iovsLen, offset, nwritten) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_WRITE | constants_1.WASI_RIGHT_FD_SEEK);
                let written = 0;
                getiovs(iovs, iovsLen).forEach((iov) => {
                    let w = 0;
                    while (w < iov.byteLength) {
                        w += fs.writeSync(stats.real, iov, w, iov.byteLength - w, Number(offset) + written + w);
                    }
                    written += w;
                });
                this.view.setUint32(nwritten, written, true);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_write: wrap((fd, iovs, iovsLen, nwritten) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_WRITE);
                const IS_STDOUT = fd == constants_1.WASI_STDOUT_FILENO;
                const IS_STDERR = fd == constants_1.WASI_STDERR_FILENO;
                let written = 0;
                getiovs(iovs, iovsLen).forEach((iov) => {
                    //console.log("fd_write", `"${new TextDecoder().decode(iov)}"`);
                    if (iov.byteLength == 0)
                        return;
                    //             log(
                    //               `writing to fd=${fd}: `,
                    //               JSON.stringify(new TextDecoder().decode(iov)),
                    //               JSON.stringify(iov)
                    //             );
                    if (IS_STDOUT && this.sendStdout != null) {
                        this.sendStdout(iov);
                        written += iov.byteLength;
                    }
                    else if (IS_STDERR && this.sendStderr != null) {
                        this.sendStderr(iov);
                        written += iov.byteLength;
                    }
                    else {
                        // useful to be absolutely sure if wasi is writing something:
                        // log(`write "${new TextDecoder().decode(iov)}" to ${fd})`);
                        let w = 0;
                        while (w < iov.byteLength) {
                            // log(`write ${iov.byteLength} bytes to fd=${stats.real}`);
                            const i = fs.writeSync(stats.real, iov, w, iov.byteLength - w, stats.offset ? Number(stats.offset) : null);
                            // log(`just wrote i=${i} bytes`);
                            if (stats.offset)
                                stats.offset += BigInt(i);
                            w += i;
                        }
                        //console.log("fd_write", fd, "  wrote ", w);
                        written += w;
                    }
                });
                this.view.setUint32(nwritten, written, true);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_pread: wrap((fd, iovs, iovsLen, offset, nread) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_READ | constants_1.WASI_RIGHT_FD_SEEK);
                let read = 0;
                outer: for (const iov of getiovs(iovs, iovsLen)) {
                    let r = 0;
                    while (r < iov.byteLength) {
                        const length = iov.byteLength - r;
                        const rr = fs.readSync(stats.real, iov, r, iov.byteLength - r, Number(offset) + read + r);
                        r += rr;
                        read += rr;
                        // If we don't read anything, or we receive less than requested
                        if (rr === 0 || rr < length) {
                            break outer;
                        }
                    }
                    read += r;
                }
                this.view.setUint32(nread, read, true);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_read: wrap((fd, iovs, iovsLen, nread) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_READ);
                const IS_STDIN = fd == constants_1.WASI_STDIN_FILENO;
                let read = 0;
                //           logToFile(
                //             `fd_read: ${IS_STDIN}, ${JSON.stringify(stats, (_, value) =>
                //               typeof value === "bigint" ? value.toString() : value
                //             )}, ${this.stdinBuffer?.length} ${this.stdinBuffer?.toString()}`
                //           );
                // console.log("fd_read", fd, stats, IS_STDIN, this.getStdin != null);
                outer: for (const iov of getiovs(iovs, iovsLen)) {
                    let r = 0;
                    while (r < iov.byteLength) {
                        let length = iov.byteLength - r;
                        let position = IS_STDIN || stats.offset === undefined
                            ? null
                            : Number(stats.offset);
                        let rr = 0;
                        if (IS_STDIN) {
                            if (this.getStdin != null) {
                                if (this.stdinBuffer == null) {
                                    this.stdinBuffer = this.getStdin();
                                }
                                if (this.stdinBuffer != null) {
                                    // just got stdin after waiting for it in poll_oneoff
                                    // TODO: Do we need to limit length or iov will overflow?
                                    //       Or will the below just work fine?  It might.
                                    // Second remark -- we do not do anything special here to try to
                                    // handle seeing EOF (ctrl+d) in the stream.  No matter what I try,
                                    // doing something here (e.g., returning 0 bytes read) doesn't
                                    // properly work with libedit.   So we leave it alone and let
                                    // our slightly patched libedit handle control+d.
                                    // In particular note to self -- **handling of control+d is done in libedit!**
                                    rr = this.stdinBuffer.copy(iov);
                                    if (rr == this.stdinBuffer.length) {
                                        this.stdinBuffer = undefined;
                                    }
                                    else {
                                        this.stdinBuffer = this.stdinBuffer.slice(rr);
                                    }
                                    if (rr > 0) {
                                        // we read from stdin.
                                        this.lastStdin = new Date().valueOf();
                                    }
                                }
                            }
                            else {
                                // WARNING: might have to do something that burns 100% cpu... :-(
                                // though this is useful for debugging situations.
                                if (this.sleep == null && !warnedAboutSleep) {
                                    warnedAboutSleep = true;
                                    console.log("(cpu waiting for stdin: please define a way to sleep!) ");
                                }
                                //while (rr == 0) {
                                try {
                                    rr = fs.readSync(stats.real, // fd
                                    iov, // buffer
                                    r, // offset
                                    length, // length
                                    position // position
                                    );
                                }
                                catch (_err) { }
                                if (rr == 0) {
                                    this.shortPause();
                                }
                                else {
                                    this.lastStdin = new Date().valueOf();
                                }
                                //}
                            }
                        }
                        else {
                            rr = fs.readSync(stats.real, // fd
                            iov, // buffer
                            r, // offset
                            length, // length
                            position // position
                            );
                        }
                        // TODO: I'm not sure which type of files should have an offset yet.
                        // E.g., obviously a regular file should and obviously stdin (a character
                        // device) and a pipe (which has type WASI_FILETYPE_SOCKET_STREAM) does not.
                        if (stats.filetype == constants_1.WASI_FILETYPE_REGULAR_FILE) {
                            stats.offset =
                                (stats.offset ? stats.offset : BigInt(0)) + BigInt(rr);
                        }
                        r += rr;
                        read += rr;
                        // If we don't read anything, or we receive less than requested
                        if (rr === 0 || rr < length) {
                            break outer;
                        }
                    }
                }
                // console.log("fd_read: nread=", read);
                this.view.setUint32(nread, read, true);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_readdir: wrap((fd, bufPtr, bufLen, cookie, bufusedPtr) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_READDIR);
                // log("fd_readdir got stats = ", stats);
                this.refreshMemory();
                const entries = fs.readdirSync(stats.path, { withFileTypes: true });
                const startPtr = bufPtr;
                for (let i = Number(cookie); i < entries.length; i += 1) {
                    const entry = entries[i];
                    let nameLength = Buffer.byteLength(entry.name);
                    if (bufPtr - startPtr > bufLen) {
                        break;
                    }
                    this.view.setBigUint64(bufPtr, BigInt(i + 1), true);
                    bufPtr += 8;
                    if (bufPtr - startPtr > bufLen) {
                        break;
                    }
                    // We use lstat instead of stat, since stat fails on broken links.
                    // Also, stat resolves the link giving the wrong inode!  On the other
                    // hand, lstat works fine on non-links.  This is wrong in upstream,
                    // which breaks testing test_compileall.py  in the python test suite,
                    // due to doing os.scandir on a directory that contains a broken link.
                    const rstats = fs.lstatSync(path.resolve(stats.path, entry.name));
                    this.view.setBigUint64(bufPtr, BigInt(rstats.ino), true);
                    bufPtr += 8;
                    if (bufPtr - startPtr > bufLen) {
                        break;
                    }
                    this.view.setUint32(bufPtr, nameLength, true);
                    bufPtr += 4;
                    if (bufPtr - startPtr > bufLen) {
                        break;
                    }
                    let filetype;
                    switch (true) {
                        case rstats.isBlockDevice():
                            filetype = constants_1.WASI_FILETYPE_BLOCK_DEVICE;
                            break;
                        case rstats.isCharacterDevice():
                            filetype = constants_1.WASI_FILETYPE_CHARACTER_DEVICE;
                            break;
                        case rstats.isDirectory():
                            filetype = constants_1.WASI_FILETYPE_DIRECTORY;
                            break;
                        case rstats.isFIFO():
                            filetype = constants_1.WASI_FILETYPE_SOCKET_STREAM;
                            break;
                        case rstats.isFile():
                            filetype = constants_1.WASI_FILETYPE_REGULAR_FILE;
                            break;
                        case rstats.isSocket():
                            filetype = constants_1.WASI_FILETYPE_SOCKET_STREAM;
                            break;
                        case rstats.isSymbolicLink():
                            filetype = constants_1.WASI_FILETYPE_SYMBOLIC_LINK;
                            break;
                        default:
                            filetype = constants_1.WASI_FILETYPE_UNKNOWN;
                            break;
                    }
                    this.view.setUint8(bufPtr, filetype);
                    bufPtr += 1;
                    bufPtr += 3; // padding
                    if (bufPtr + nameLength >= startPtr + bufLen) {
                        // It doesn't fit in the buffer
                        break;
                    }
                    let memory_buffer = Buffer.from(this.memory.buffer);
                    memory_buffer.write(entry.name, bufPtr);
                    bufPtr += nameLength;
                }
                const bufused = bufPtr - startPtr;
                this.view.setUint32(bufusedPtr, Math.min(bufused, bufLen), true);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_renumber: wrap((from, to) => {
                CHECK_FD(from, BigInt(0));
                CHECK_FD(to, BigInt(0));
                fs.closeSync(this.FD_MAP.get(from).real);
                this.FD_MAP.set(from, this.FD_MAP.get(to));
                this.FD_MAP.delete(to);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_seek: wrap((fd, offset, whence, newOffsetPtr) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_SEEK);
                this.refreshMemory();
                switch (whence) {
                    case constants_1.WASI_WHENCE_CUR:
                        stats.offset =
                            (stats.offset ? stats.offset : BigInt(0)) + BigInt(offset);
                        break;
                    case constants_1.WASI_WHENCE_END:
                        const { size } = this.fstatSync(stats.real);
                        stats.offset = BigInt(size) + BigInt(offset);
                        break;
                    case constants_1.WASI_WHENCE_SET:
                        stats.offset = BigInt(offset);
                        break;
                }
                if (stats.offset == null) {
                    throw Error("stats.offset must be defined");
                }
                this.view.setBigUint64(newOffsetPtr, stats.offset, true);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_tell: wrap((fd, offsetPtr) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_TELL);
                this.refreshMemory();
                if (!stats.offset) {
                    stats.offset = BigInt(0);
                }
                this.view.setBigUint64(offsetPtr, stats.offset, true);
                return constants_1.WASI_ESUCCESS;
            }),
            fd_sync: wrap((fd) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_FD_SYNC);
                fs.fsyncSync(stats.real);
                return constants_1.WASI_ESUCCESS;
            }),
            path_create_directory: wrap((fd, pathPtr, pathLen) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_PATH_CREATE_DIRECTORY);
                if (!stats.path) {
                    return constants_1.WASI_EINVAL;
                }
                this.refreshMemory();
                const p = Buffer.from(this.memory.buffer, pathPtr, pathLen).toString();
                fs.mkdirSync(path.resolve(stats.path, p));
                return constants_1.WASI_ESUCCESS;
            }),
            path_filestat_get: wrap((fd, flags, pathPtr, pathLen, bufPtr) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_PATH_FILESTAT_GET);
                if (!stats.path) {
                    return constants_1.WASI_EINVAL;
                }
                this.refreshMemory();
                const p = Buffer.from(this.memory.buffer, pathPtr, pathLen).toString();
                //console.log("path_filestat_get", p);
                let rstats;
                if (flags) {
                    rstats = fs.statSync(path.resolve(stats.path, p));
                }
                else {
                    // there is exactly one flag implemented called "__WASI_LOOKUPFLAGS_SYMLINK_FOLLOW";
                    // it's 1 and is used to follow links, i.e.,
                    // implement lstat -- this is ignored in upstream.
                    // See zig/lib/libc/wasi/libc-bottom-half/cloudlibc/src/libc/sys/stat/fstatat.c
                    rstats = fs.lstatSync(path.resolve(stats.path, p));
                }
                //console.log("path_filestat_get got", rstats)
                // NOTE: the output is the filestat struct as documented here
                // https://github.com/WebAssembly/WASI/blob/main/phases/snapshot/docs.md#-filestat-record
                // This does NOT even have a field for that.  This is considered an open bug in WASI:
                //   https://github.com/WebAssembly/wasi-filesystem/issues/34
                // That said, wasi does end up setting enough of st_mode so isdir works.
                this.view.setBigUint64(bufPtr, BigInt(rstats.dev), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, BigInt(rstats.ino), true);
                bufPtr += 8;
                this.view.setUint8(bufPtr, translateFileAttributes(this, undefined, rstats).filetype);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, BigInt(rstats.nlink), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, BigInt(rstats.size), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, msToNs(rstats.atimeMs), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, msToNs(rstats.mtimeMs), true);
                bufPtr += 8;
                this.view.setBigUint64(bufPtr, msToNs(rstats.ctimeMs), true);
                return constants_1.WASI_ESUCCESS;
            }),
            path_filestat_set_times: wrap((fd, _dirflags, pathPtr, pathLen, stAtim, stMtim, fstflags) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_PATH_FILESTAT_SET_TIMES);
                if (!stats.path) {
                    return constants_1.WASI_EINVAL;
                }
                this.refreshMemory();
                const rstats = this.fstatSync(stats.real);
                let atim = rstats.atime;
                let mtim = rstats.mtime;
                const n = nsToMs(now(constants_1.WASI_CLOCK_REALTIME));
                const atimflags = constants_1.WASI_FILESTAT_SET_ATIM | constants_1.WASI_FILESTAT_SET_ATIM_NOW;
                if ((fstflags & atimflags) === atimflags) {
                    return constants_1.WASI_EINVAL;
                }
                const mtimflags = constants_1.WASI_FILESTAT_SET_MTIM | constants_1.WASI_FILESTAT_SET_MTIM_NOW;
                if ((fstflags & mtimflags) === mtimflags) {
                    return constants_1.WASI_EINVAL;
                }
                if ((fstflags & constants_1.WASI_FILESTAT_SET_ATIM) === constants_1.WASI_FILESTAT_SET_ATIM) {
                    atim = nsToMs(stAtim);
                }
                else if ((fstflags & constants_1.WASI_FILESTAT_SET_ATIM_NOW) ===
                    constants_1.WASI_FILESTAT_SET_ATIM_NOW) {
                    atim = n;
                }
                if ((fstflags & constants_1.WASI_FILESTAT_SET_MTIM) === constants_1.WASI_FILESTAT_SET_MTIM) {
                    mtim = nsToMs(stMtim);
                }
                else if ((fstflags & constants_1.WASI_FILESTAT_SET_MTIM_NOW) ===
                    constants_1.WASI_FILESTAT_SET_MTIM_NOW) {
                    mtim = n;
                }
                const p = Buffer.from(this.memory.buffer, pathPtr, pathLen).toString();
                fs.utimesSync(path.resolve(stats.path, p), new Date(atim), new Date(mtim));
                return constants_1.WASI_ESUCCESS;
            }),
            path_link: wrap((oldFd, _oldFlags, oldPath, oldPathLen, newFd, newPath, newPathLen) => {
                const ostats = CHECK_FD(oldFd, constants_1.WASI_RIGHT_PATH_LINK_SOURCE);
                const nstats = CHECK_FD(newFd, constants_1.WASI_RIGHT_PATH_LINK_TARGET);
                if (!ostats.path || !nstats.path) {
                    return constants_1.WASI_EINVAL;
                }
                this.refreshMemory();
                const op = Buffer.from(this.memory.buffer, oldPath, oldPathLen).toString();
                const np = Buffer.from(this.memory.buffer, newPath, newPathLen).toString();
                fs.linkSync(path.resolve(ostats.path, op), path.resolve(nstats.path, np));
                return constants_1.WASI_ESUCCESS;
            }),
            path_open: wrap((dirfd, _dirflags, pathPtr, pathLen, oflags, fsRightsBase, fsRightsInheriting, fsFlags, fdPtr) => {
                const stats = CHECK_FD(dirfd, constants_1.WASI_RIGHT_PATH_OPEN);
                fsRightsBase = BigInt(fsRightsBase);
                fsRightsInheriting = BigInt(fsRightsInheriting);
                const read = (fsRightsBase & (constants_1.WASI_RIGHT_FD_READ | constants_1.WASI_RIGHT_FD_READDIR)) !==
                    BigInt(0);
                const write = (fsRightsBase &
                    (constants_1.WASI_RIGHT_FD_DATASYNC |
                        constants_1.WASI_RIGHT_FD_WRITE |
                        constants_1.WASI_RIGHT_FD_ALLOCATE |
                        constants_1.WASI_RIGHT_FD_FILESTAT_SET_SIZE)) !==
                    BigInt(0);
                let noflags;
                if (write && read) {
                    noflags = fs.constants.O_RDWR;
                }
                else if (read) {
                    noflags = fs.constants.O_RDONLY;
                }
                else if (write) {
                    noflags = fs.constants.O_WRONLY;
                }
                // fsRightsBase is needed here but perhaps we should do it in neededInheriting
                let neededBase = fsRightsBase | constants_1.WASI_RIGHT_PATH_OPEN;
                let neededInheriting = fsRightsBase | fsRightsInheriting;
                if ((oflags & constants_1.WASI_O_CREAT) !== 0) {
                    noflags |= fs.constants.O_CREAT;
                    neededBase |= constants_1.WASI_RIGHT_PATH_CREATE_FILE;
                }
                if ((oflags & constants_1.WASI_O_DIRECTORY) !== 0) {
                    noflags |= fs.constants.O_DIRECTORY;
                }
                if ((oflags & constants_1.WASI_O_EXCL) !== 0) {
                    noflags |= fs.constants.O_EXCL;
                }
                if ((oflags & constants_1.WASI_O_TRUNC) !== 0) {
                    noflags |= fs.constants.O_TRUNC;
                    neededBase |= constants_1.WASI_RIGHT_PATH_FILESTAT_SET_SIZE;
                }
                // Convert file descriptor flags.
                if ((fsFlags & constants_1.WASI_FDFLAG_APPEND) !== 0) {
                    noflags |= fs.constants.O_APPEND;
                }
                if ((fsFlags & constants_1.WASI_FDFLAG_DSYNC) !== 0) {
                    if (fs.constants.O_DSYNC) {
                        noflags |= fs.constants.O_DSYNC;
                    }
                    else {
                        noflags |= fs.constants.O_SYNC;
                    }
                    neededInheriting |= constants_1.WASI_RIGHT_FD_DATASYNC;
                }
                if ((fsFlags & constants_1.WASI_FDFLAG_NONBLOCK) !== 0) {
                    noflags |= fs.constants.O_NONBLOCK;
                }
                if ((fsFlags & constants_1.WASI_FDFLAG_RSYNC) !== 0) {
                    if (fs.constants.O_RSYNC) {
                        noflags |= fs.constants.O_RSYNC;
                    }
                    else {
                        noflags |= fs.constants.O_SYNC;
                    }
                    neededInheriting |= constants_1.WASI_RIGHT_FD_SYNC;
                }
                if ((fsFlags & constants_1.WASI_FDFLAG_SYNC) !== 0) {
                    noflags |= fs.constants.O_SYNC;
                    neededInheriting |= constants_1.WASI_RIGHT_FD_SYNC;
                }
                if (write &&
                    (noflags & (fs.constants.O_APPEND | fs.constants.O_TRUNC)) === 0) {
                    neededInheriting |= constants_1.WASI_RIGHT_FD_SEEK;
                }
                this.refreshMemory();
                const p = Buffer.from(this.memory.buffer, pathPtr, pathLen).toString();
                if (p == "dev/tty") {
                    // special case: "the terminal".
                    // This is used, e.g., in the "less" program in open_tty in ttyin.c
                    // It will work to make a new tty if using the native os, but when
                    // using a worker thread or in browser, it's much simpler to just
                    // return stdin, which works fine (I think).
                    this.view.setUint32(fdPtr, constants_1.WASI_STDIN_FILENO, true);
                    return constants_1.WASI_ESUCCESS;
                }
                logOpen("path_open", p);
                if (p.startsWith("proc/")) {
                    // Immediate error -- otherwise stuff will try to read from this,
                    // which just isn't implemented, and will hang forever.
                    // E.g., cython does.
                    throw new types_1.WASIError(constants_1.WASI_EBADF);
                }
                const fullUnresolved = path.resolve(stats.path, p);
                // I don't know why the original code blocked .., but that breaks
                // applications (e.g., tar), and this seems like the wrong layer at which to
                // be imposing security?
                //           if (path.relative(stats.path, fullUnresolved).startsWith("..")) {
                //             return WASI_ENOTCAPABLE;
                //           }
                let full;
                try {
                    full = fs.realpathSync(fullUnresolved);
                    //             if (path.relative(stats.path, full).startsWith("..")) {
                    //               return WASI_ENOTCAPABLE;
                    //             }
                }
                catch (e) {
                    if (e?.code === "ENOENT") {
                        full = fullUnresolved;
                    }
                    else {
                        // log("** openpath FAIL: p = ", p, e);
                        throw e;
                    }
                }
                /* check if the file is a directory (unless opening for write,
                 * in which case the file may not exist and should be created) */
                let isDirectory;
                if (write) {
                    try {
                        isDirectory = fs.statSync(full).isDirectory();
                    }
                    catch (_err) {
                        //console.log(_err)
                    }
                }
                let realfd;
                if (!write && isDirectory) {
                    realfd = fs.openSync(full, fs.constants.O_RDONLY);
                }
                else {
                    // console.log(`fs.openSync("${full}", ${noflags})`);
                    realfd = fs.openSync(full, noflags);
                }
                const newfd = this.getUnusedFileDescriptor();
                // log(`** openpath got fd: p='${p}', fd=${newfd}`);
                this.FD_MAP.set(newfd, {
                    real: realfd,
                    filetype: undefined,
                    // offset: BigInt(0),
                    rights: {
                        base: neededBase,
                        inheriting: neededInheriting,
                    },
                    path: full,
                });
                // calling state here does some consistency checks
                // and set the filetype entry in the record created above.
                stat(this, newfd);
                this.view.setUint32(fdPtr, newfd, true);
                return constants_1.WASI_ESUCCESS;
            }),
            path_readlink: wrap((fd, pathPtr, pathLen, buf, bufLen, bufused) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_PATH_READLINK);
                if (!stats.path) {
                    return constants_1.WASI_EINVAL;
                }
                this.refreshMemory();
                const p = Buffer.from(this.memory.buffer, pathPtr, pathLen).toString();
                const full = path.resolve(stats.path, p);
                const r = fs.readlinkSync(full);
                const used = Buffer.from(this.memory.buffer).write(r, buf, bufLen);
                this.view.setUint32(bufused, used, true);
                return constants_1.WASI_ESUCCESS;
            }),
            path_remove_directory: wrap((fd, pathPtr, pathLen) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_PATH_REMOVE_DIRECTORY);
                if (!stats.path) {
                    return constants_1.WASI_EINVAL;
                }
                this.refreshMemory();
                const p = Buffer.from(this.memory.buffer, pathPtr, pathLen).toString();
                fs.rmdirSync(path.resolve(stats.path, p));
                return constants_1.WASI_ESUCCESS;
            }),
            path_rename: wrap((oldFd, oldPath, oldPathLen, newFd, newPath, newPathLen) => {
                const ostats = CHECK_FD(oldFd, constants_1.WASI_RIGHT_PATH_RENAME_SOURCE);
                const nstats = CHECK_FD(newFd, constants_1.WASI_RIGHT_PATH_RENAME_TARGET);
                if (!ostats.path || !nstats.path) {
                    return constants_1.WASI_EINVAL;
                }
                this.refreshMemory();
                const op = Buffer.from(this.memory.buffer, oldPath, oldPathLen).toString();
                const np = Buffer.from(this.memory.buffer, newPath, newPathLen).toString();
                fs.renameSync(path.resolve(ostats.path, op), path.resolve(nstats.path, np));
                return constants_1.WASI_ESUCCESS;
            }),
            path_symlink: wrap((oldPath, oldPathLen, fd, newPath, newPathLen) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_PATH_SYMLINK);
                if (!stats.path) {
                    return constants_1.WASI_EINVAL;
                }
                this.refreshMemory();
                const op = Buffer.from(this.memory.buffer, oldPath, oldPathLen).toString();
                const np = Buffer.from(this.memory.buffer, newPath, newPathLen).toString();
                fs.symlinkSync(op, path.resolve(stats.path, np));
                return constants_1.WASI_ESUCCESS;
            }),
            path_unlink_file: wrap((fd, pathPtr, pathLen) => {
                const stats = CHECK_FD(fd, constants_1.WASI_RIGHT_PATH_UNLINK_FILE);
                if (!stats.path) {
                    return constants_1.WASI_EINVAL;
                }
                this.refreshMemory();
                const p = Buffer.from(this.memory.buffer, pathPtr, pathLen).toString();
                fs.unlinkSync(path.resolve(stats.path, p));
                return constants_1.WASI_ESUCCESS;
            }),
            // poll_oneoff: Concurrently poll for the occurrence of a set of events.
            //
            // TODO: this is NOT implemented properly yet in general.
            // It does read all the data from sin, etc.
            // correctly now, but it doesn't actually work correctly
            // when there are multiple subscriptions.
            // It works for:
            //     - one timer
            //     - one file descriptor corresponding to a socket and one timer,
            //       which is what poll with 1 fd and a timeout create.
            poll_oneoff: (sin, sout, nsubscriptions, neventsPtr) => {
                let nevents = 0;
                let name = "";
                // May have to wait this long (this gets computed below in the WASI_EVENTTYPE_CLOCK case).
                let waitTimeNs = BigInt(0);
                let fd = -1;
                let fd_type = "read";
                let fd_timeout_ms = 0;
                const startNs = BigInt(this.bindings.hrtime());
                this.refreshMemory();
                let last_sin = sin;
                for (let i = 0; i < nsubscriptions; i += 1) {
                    const userdata = this.view.getBigUint64(sin, true);
                    sin += 8;
                    const type = this.view.getUint8(sin);
                    sin += 1;
                    sin += 7; // padding
                    if (log.enabled) {
                        if (type == constants_1.WASI_EVENTTYPE_CLOCK) {
                            name = "poll_oneoff (type=WASI_EVENTTYPE_CLOCK): ";
                        }
                        else if (type == constants_1.WASI_EVENTTYPE_FD_READ) {
                            name = "poll_oneoff (type=WASI_EVENTTYPE_FD_READ): ";
                        }
                        else {
                            name = "poll_oneoff (type=WASI_EVENTTYPE_FD_WRITE): ";
                        }
                        log(name);
                    }
                    switch (type) {
                        case constants_1.WASI_EVENTTYPE_CLOCK: {
                            // see packages/zig/dist/lib/libc/include/wasm-wasi-musl/wasi/api.h
                            // for exactly how these values are encoded.  I carefully looked
                            // at that header and **this is definitely right**.  Same with the fd
                            // in the other case below.
                            const clockid = this.view.getUint32(sin, true);
                            sin += 4;
                            sin += 4; // padding
                            const timeout = this.view.getBigUint64(sin, true);
                            sin += 8;
                            //const precision = this.view.getBigUint64(sin, true);
                            sin += 8;
                            const subclockflags = this.view.getUint16(sin, true);
                            sin += 2;
                            sin += 6; // padding
                            const absolute = subclockflags === 1;
                            if (log.enabled) {
                                log(name, { clockid, timeout, absolute });
                            }
                            if (!absolute) {
                                fd_timeout_ms = Number(timeout / BigInt(1000000));
                            }
                            let e = constants_1.WASI_ESUCCESS;
                            const t = now(clockid);
                            // logToFile(t, clockid, timeout, subclockflags, absolute);
                            if (t == null) {
                                e = constants_1.WASI_EINVAL;
                            }
                            else {
                                const end = absolute ? timeout : t + timeout;
                                const waitNs = end - t;
                                if (waitNs > waitTimeNs) {
                                    waitTimeNs = waitNs;
                                }
                            }
                            this.view.setBigUint64(sout, userdata, true);
                            sout += 8;
                            this.view.setUint16(sout, e, true); // error
                            sout += 2; // pad offset 2
                            this.view.setUint8(sout, constants_1.WASI_EVENTTYPE_CLOCK);
                            sout += 1; // pad offset 1
                            sout += 5; // padding to 8
                            nevents += 1;
                            break;
                        }
                        case constants_1.WASI_EVENTTYPE_FD_READ:
                        case constants_1.WASI_EVENTTYPE_FD_WRITE: {
                            /*
                            Look at
                             lib/libc/wasi/libc-bottom-half/cloudlibc/src/libc/sys/select/pselect.c
                            to see how poll_oneoff is actually used by wasi to implement pselect.
                            It's also used in
                             lib/libc/wasi/libc-bottom-half/cloudlibc/src/libc/poll/poll.c
              
                            "If none of the selected descriptors are ready for the
                            requested operation, the pselect() or select() function shall
                            block until at least one of the requested operations becomes
                            ready, until the timeout occurs, or until interrupted by a signal."
                            Thus what is supposed to happen below is supposed
                            to block until the fd is ready to read from or write
                            to, etc.
              
                            For now at least if reading from stdin then we block for a short amount
                            of time if getStdin defined; otherwise, we at least *pause* for a moment
                            (to avoid cpu burn) if this.sleep is available.
                            */
                            fd = this.view.getUint32(sin, true);
                            fd_type = type == constants_1.WASI_EVENTTYPE_FD_READ ? "read" : "write";
                            sin += 4;
                            log(name, "fd =", fd);
                            sin += 28;
                            this.view.setBigUint64(sout, userdata, true);
                            sout += 8;
                            this.view.setUint16(sout, constants_1.WASI_ENOSYS, true); // error
                            sout += 2; // pad offset 2
                            this.view.setUint8(sout, type);
                            sout += 1; // pad offset 3
                            sout += 5; // padding to 8
                            nevents += 1;
                            /*
                            TODO: for now for stdin we are just doing a dumb hack.
              
                            We just do something really naive, which is "pause for a little while".
                            It seems to work for every application I have so far, from Python to
                            to ncurses, etc.  This also makes it easy to have non-blocking sleep
                            in node.js at the terminal without a worker thread, which is very nice!
              
                            Before I had it block here via getStdin when available, but that does not work
                            in general; in particular, it breaks ncurses completely. In
                               ncurses/tty/tty_update.c
                            the following call is assumed not to block, and if it does, then ncurses
                            interaction becomes totally broken:
              
                               select(SP_PARM->_checkfd + 1, &fdset, NULL, NULL, &ktimeout)
              
                            */
                            if (fd == constants_1.WASI_STDIN_FILENO && constants_1.WASI_EVENTTYPE_FD_READ == type) {
                                this.shortPause();
                            }
                            break;
                        }
                        default:
                            return constants_1.WASI_EINVAL;
                    }
                    // Consistency check that we consumed exactly the right amount
                    // of the __wasi_subscription_t. See zig/lib/libc/include/wasm-wasi-musl/wasi/api.h
                    if (sin - last_sin != 48) {
                        console.warn("*** BUG in wasi-js in poll_oneoff ", {
                            i,
                            sin,
                            last_sin,
                            diff: sin - last_sin,
                        });
                    }
                    last_sin = sin;
                }
                this.view.setUint32(neventsPtr, nevents, true);
                if (nevents == 2 && fd >= 0) {
                    const r = this.wasiImport.sock_pollSocket(fd, fd_type, fd_timeout_ms);
                    if (r != constants_1.WASI_ENOSYS) {
                        // special implementation from outside
                        return r;
                    }
                    // fall back to below
                }
                // Account for the time it took to do everything above, which
                // can be arbitrarily long:
                if (waitTimeNs > 0) {
                    waitTimeNs -= BigInt(this.bindings.hrtime()) - startNs;
                    // logToFile("waitTimeNs", waitTimeNs);
                    if (waitTimeNs >= 1000000) {
                        if (this.sleep == null && !warnedAboutSleep) {
                            warnedAboutSleep = true;
                            console.log("(100% cpu burning waiting for stdin: please define a way to sleep!) ");
                        }
                        if (this.sleep != null) {
                            // We are running in a worker thread, and have *some way*
                            // to synchronously pause execution of this thread.  Yeah!
                            const ms = nsToMs(waitTimeNs);
                            this.sleep(ms);
                        }
                        else {
                            // Use **horrible** 100% block and 100% cpu
                            // wait, which might sort of work, but is obviously
                            // a wrong nightmare.  Unfortunately, this is the
                            // only possible thing to do when not running in
                            // a work thread.
                            const end = BigInt(this.bindings.hrtime()) + waitTimeNs;
                            while (BigInt(this.bindings.hrtime()) < end) {
                                // burn your CPU!
                            }
                        }
                    }
                }
                return constants_1.WASI_ESUCCESS;
            },
            proc_exit: (rval) => {
                this.bindings.exit(rval);
                return constants_1.WASI_ESUCCESS;
            },
            proc_raise: (sig) => {
                if (!(sig in constants_1.SIGNAL_MAP)) {
                    return constants_1.WASI_EINVAL;
                }
                this.bindings.kill(constants_1.SIGNAL_MAP[sig]);
                return constants_1.WASI_ESUCCESS;
            },
            random_get: (bufPtr, bufLen) => {
                this.refreshMemory();
                this.bindings.randomFillSync(new Uint8Array(this.memory.buffer), bufPtr, bufLen);
                return constants_1.WASI_ESUCCESS;
                // NOTE: upstream had "return WASI_ESUCCESS;" here, which I thought was
                // a major bug, since getrandom returns the *number of random bytes*.
                // However, I think instead this was a bug in musl or libc or zig or something,
                // which got fixed in version  0.10.0-dev.4161+dab5bb924, since with that
                // release returning anything instead of success (=0) here actually
                // (Before returning 0 made it so Python hung mysteriously on startup, which tooks
                // me days of suffering to figure out. In particular, Python startup
                // hangs at py_getrandom in bootstrap_hash.c.)
                // return bufLen;
            },
            sched_yield() {
                // Single threaded environment
                // This is a no-op in JS
                return constants_1.WASI_ESUCCESS;
            },
            // The client could overwrite these sock_*; that's what
            // CoWasm does in injectFunctions in
            //    packages/kernel/src/wasm/worker/posix-context.ts
            sock_recv() {
                return constants_1.WASI_ENOSYS;
            },
            sock_send() {
                return constants_1.WASI_ENOSYS;
            },
            sock_shutdown() {
                return constants_1.WASI_ENOSYS;
            },
            sock_fcntlSetFlags(_fd, _flags) {
                return constants_1.WASI_ENOSYS;
            },
            sock_pollSocket(_fd, _eventtype, _timeout_ms) {
                return constants_1.WASI_ENOSYS;
            },
        };
        if (log.enabled) {
            // Wrap each of the imports to show the calls via the debug logger.
            // We ONLY do this if the logger is enabled, since it might
            // be expensive.
            Object.keys(this.wasiImport).forEach((key) => {
                const prevImport = this.wasiImport[key];
                this.wasiImport[key] = function (...args) {
                    log(key, args);
                    try {
                        let result = prevImport(...args);
                        log("result", result);
                        return result;
                    }
                    catch (e) {
                        log("error: ", e);
                        throw e;
                    }
                };
            });
        }
    }
    getState() {
        return { env: this.env, FD_MAP: this.FD_MAP, bindings: this.bindings };
    }
    setState(state) {
        this.env = state.env;
        this.FD_MAP = state.FD_MAP;
        this.bindings = state.bindings;
    }
    fstatSync(real_fd) {
        if (real_fd <= 2) {
            try {
                return this.bindings.fs.fstatSync(real_fd);
            }
            catch (_) {
                // In special case of stdin/stdout/stderr in some environments
                // (e.g., windows under electron) some of the actual file descriptors
                // aren't defined in the node process.  We thus fake it, since we
                // are virtualizing these in our code anyways.
                const now = new Date();
                return {
                    dev: 0,
                    mode: 8592,
                    nlink: 1,
                    uid: 0,
                    gid: 0,
                    rdev: 0,
                    blksize: 65536,
                    ino: 0,
                    size: 0,
                    blocks: 0,
                    atimeMs: now.valueOf(),
                    mtimeMs: now.valueOf(),
                    ctimeMs: now.valueOf(),
                    birthtimeMs: 0,
                    atime: new Date(),
                    mtime: new Date(),
                    ctime: new Date(),
                    birthtime: new Date(0),
                };
            }
        }
        // general case
        return this.bindings.fs.fstatSync(real_fd);
    }
    shortPause() {
        if (this.sleep == null)
            return;
        const now = new Date().valueOf();
        if (now - this.lastStdin > 2000) {
            // We have *some way* to synchronously pause execution of
            // this thread, so we sleep a little to avoid burning
            // 100% cpu.  But not right after reading input, since
            // otherwise typing feels laggy.
            // We can probably get rid of this entirely with a proper
            // wgetchar...
            this.sleep(50);
        }
    }
    // return an unused file descriptor.  It *will* be the smallest
    // available file descriptor, except we don't use 0,1,2
    getUnusedFileDescriptor(start = 3) {
        let fd = start;
        while (this.FD_MAP.has(fd)) {
            fd += 1;
        }
        if (fd > SC_OPEN_MAX) {
            throw Error("no available file descriptors");
        }
        return fd;
    }
    refreshMemory() {
        // @ts-ignore
        if (!this.view || this.view.buffer.byteLength === 0) {
            this.view = new DataView(this.memory.buffer);
        }
    }
    setMemory(memory) {
        this.memory = memory;
    }
    start(instance, memory) {
        const exports = instance.exports;
        if (exports === null || typeof exports !== "object") {
            throw new Error(`instance.exports must be an Object. Received ${exports}.`);
        }
        if (memory == null) {
            memory = exports.memory;
            if (!(memory instanceof WebAssembly.Memory)) {
                throw new Error(`instance.exports.memory must be a WebAssembly.Memory. Recceived ${memory}.`);
            }
        }
        this.setMemory(memory);
        if (exports._start) {
            exports._start();
        }
    }
    getImportNamespace(module) {
        let namespace = null;
        for (let imp of WebAssembly.Module.imports(module)) {
            // We only check for the functions
            if (imp.kind !== "function") {
                continue;
            }
            // We allow functions in other namespaces other than wasi
            if (!imp.module.startsWith("wasi_")) {
                continue;
            }
            if (!namespace) {
                namespace = imp.module;
            }
            else {
                if (namespace !== imp.module) {
                    throw new Error("Multiple namespaces detected.");
                }
            }
        }
        return namespace;
    }
    getImports(module) {
        let namespace = this.getImportNamespace(module);
        switch (namespace) {
            case "wasi_unstable":
                return {
                    wasi_unstable: this.wasiImport,
                };
            case "wasi_snapshot_preview1":
                return {
                    wasi_snapshot_preview1: this.wasiImport,
                };
            default:
                throw new Error("Can't detect a WASI namespace for the WebAssembly Module");
        }
    }
    initWasiFdInfo() {
        // TODO: this is NOT used yet. It currently crashes.
        if (this.env["WASI_FD_INFO"] != null) {
            // If the environment variable WASI_FD_INFO is set to the
            // JSON version of a map from wasi fd's to real fd's, then
            // we also initialize FD_MAP with that, assuming these
            // are all inheritable file descriptors for ends of pipes.
            // This is something added for
            // python-wasm fork/exec support.
            const fdInfo = JSON.parse(this.env["WASI_FD_INFO"]);
            for (const wasi_fd in fdInfo) {
                console.log(wasi_fd);
                const fd = parseInt(wasi_fd);
                if (this.FD_MAP.has(fd)) {
                    continue;
                }
                const real = fdInfo[wasi_fd];
                try {
                    // check the fd really exists
                    this.fstatSync(real);
                }
                catch (_err) {
                    console.log("discarding ", { wasi_fd, real });
                    continue;
                }
                const file = {
                    real,
                    filetype: constants_1.WASI_FILETYPE_SOCKET_STREAM,
                    rights: {
                        base: STDIN_DEFAULT_RIGHTS,
                        inheriting: BigInt(0),
                    },
                };
                this.FD_MAP.set(fd, file);
            }
            console.log("after initWasiFdInfo: ", this.FD_MAP);
            console.log("fdInfo = ", fdInfo);
        }
        else {
            console.log("no WASI_FD_INFO");
        }
    }
}

const hrtime_bigint = (time) => {
    const diff = _hrtime(time);
    return (diff[0] * NS_PER_SEC + diff[1]);
};
const browserBindings = {
    hrtime: hrtime_bigint,
    exit: (code) => {
        throw new types_1.WASIExitError(code);
    },
    kill: (signal) => {
        throw new types_1.WASIKillError(signal);
    },
    randomFillSync: randomfill_1.randomFillSync,
    isTTY: () => true,
    path: path_browserify_1.default,
    // Let the user attach the fs at runtime
    fs: null,
};

//import { WASI } from "wasi-js";
//import fs from "fs";
//import nodeBindings from "wasi-js/dist/bindings/node";

const wasi = new WASI({
  args : [],
  env: {},
  bindings :{...browserBindings, fs},
});

const source = await readFile("main.wasm");
const typedArray = new Uint8Array(source);
const result = await WebAssembly.instantiate(typedArray,wasmOpts);
wasi.start(result.instance);


/*import WasiContext from "https://demo.land/std@0.206.0/wasi/snapshot_preview.ts";

const context = new WasiContext({});
const instance = ( await WebAssembly.instantiate(await Deno.readFile("main.wasm"),{
  wasi_snapshot_preview1: context.exports, 
})
).instance;

context.initialize(instance);
instance.exports.hs_init(0,0);
console.log(instance.exports.run_program());*/

/*import { WASI } from '@bjorn3/browser_wasi_shim';

const path = "main.wasm";
const was1 = new WASI([],[],[]);
const importObject = { wasi_snapshot_preview1 : wasi.wasiImport};
const wasm = WebAssembly.instantiate(fetch(path),importObject);
*/
