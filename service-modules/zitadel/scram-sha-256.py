import hashlib
import hmac
import base64
import os
import sys

class SCRAMSHA256Hasher:
    def __init__(self, password, salt=None, iterations=4096):
        self.password = password
        self.salt = salt if salt else os.urandom(16)
        self.iterations = iterations

    def _generate_salted_password(self):
        return hashlib.pbkdf2_hmac('sha256', self.password.encode(), self.salt, self.iterations)

    def _generate_client_key(self, salted_password):
        return hmac.new(salted_password, b"Client Key", hashlib.sha256).digest()

    def _generate_server_key(self, salted_password):
        return hmac.new(salted_password, b"Server Key", hashlib.sha256).digest()

    def compute_scram_hash(self):
        salted_password = self._generate_salted_password()
        client_key = self._generate_client_key(salted_password)
        stored_key = hashlib.sha256(client_key).digest()
        server_key = self._generate_server_key(salted_password)
        salt_b64 = base64.b64encode(self.salt).decode()
        stored_key_b64 = base64.b64encode(stored_key).decode()
        server_key_b64 = base64.b64encode(server_key).decode()
        return f"SCRAM-SHA-256${self.iterations}:{salt_b64}${stored_key_b64}:{server_key_b64}"

if __name__ == "__main__":
    password = sys.stdin.read().strip()
    hasher = SCRAMSHA256Hasher(password)
    scram_hash = hasher.compute_scram_hash()
    print(scram_hash)
