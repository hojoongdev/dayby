"""Password hashing for local accounts (AUTH_PROVIDER=password).

pbkdf2 from the standard library, so a password account needs no extra dependency.
The stored string carries its own algorithm, iteration count and salt, so the cost
can be raised later without stranding the hashes already written.
"""
import hashlib
import hmac
import secrets

_ALGORITHM = "pbkdf2_sha256"
_ITERATIONS = 200_000


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode(), bytes.fromhex(salt), _ITERATIONS
    ).hex()
    return f"{_ALGORITHM}${_ITERATIONS}${salt}${digest}"


def verify_password(password: str, stored: str) -> bool:
    """True if the password matches the stored hash. False on any malformed hash."""
    try:
        algorithm, iterations, salt, digest = stored.split("$")
        if algorithm != _ALGORITHM:
            return False
        expected = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), bytes.fromhex(salt), int(iterations)
        ).hex()
    except (ValueError, AttributeError):
        return False
    # Constant-time, so a wrong password cannot be narrowed down by timing.
    return hmac.compare_digest(expected, digest)
