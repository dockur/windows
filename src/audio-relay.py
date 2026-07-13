import os, socket, threading
FIFO = '/run/audio.fifo'; PORT = 4712
clients = set(); lock = threading.Lock()
def accept_loop():
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', PORT)); srv.listen(16)
    while True:
        c, _ = srv.accept()
        c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        with lock: clients.add(c)
threading.Thread(target=accept_loop, daemon=True).start()
while True:
    fd = os.open(FIFO, os.O_RDONLY)
    while True:
        data = os.read(fd, 4096)
        if not data: break
        with lock:
            for c in list(clients):
                try: c.sendall(data)
                except Exception:
                    clients.discard(c)
                    try: c.close()
                    except Exception: pass
    os.close(fd)
