#!/bin/bash
set -e

###############################################################################
# WAPT - Python 2.7 compatibility runtime for Debian 12
#
# Transitional compatibility runtime for WAPT Server 1.8.2.
#
# IMPORTANT:
#   Python 2.7 is EOL.
#   This runtime is a compatibility layer, NOT the final security architecture.
#
# Output:
#   /git/waptdev/build/python2-runtime-server/
#
###############################################################################

PYTHON_VERSION="2.7.18"

BUILD_ROOT="/tmp/wapt-python2-build"
PYTHON_SRC="${BUILD_ROOT}/Python-${PYTHON_VERSION}"

RUNTIME_ROOT="/git/waptdev/build/python2-runtime-server"

PIP_VERSION="20.3.4"
SETUPTOOLS_VERSION="44.1.1"
WHEEL_VERSION="0.34.2"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PYTHON="${RUNTIME_ROOT}/bin/python"
PIP="${RUNTIME_ROOT}/bin/pip"

###############################################################################
# Helpers
###############################################################################

die()
{
    echo
    echo "ERROR: $*"
    exit 1
}

run()
{
    echo
    echo ">>> $*"
    "$@"
}

###############################################################################
# Header
###############################################################################

echo "============================================================"
echo " WAPT Python 2 compatibility runtime"
echo " Debian 12"
echo " WAPT Server"
echo " Python ${PYTHON_VERSION}"
echo "============================================================"

###############################################################################
# 1. Checks
###############################################################################

[ "$(id -u)" -eq 0 ] || die "run this script as root (sudo)."

[ -d "${REPO_ROOT}" ] || die "repository not found: ${REPO_ROOT}"

[ -f "${REPO_ROOT}/requirements-server.txt" ] \
    || die "requirements-server.txt not found"

[ -f "${REPO_ROOT}/utils/patch-cryptography/__init__.py" ] \
    || die "WAPT cryptography patch not found"

[ -f "${REPO_ROOT}/utils/patch-cryptography/verification.py" ] \
    || die "WAPT cryptography verification patch not found"

echo
echo ">>> Repository:"
echo "    ${REPO_ROOT}"

echo
echo ">>> Build output:"
echo "    ${RUNTIME_ROOT}"

###############################################################################
# 2. Build dependencies
###############################################################################

echo
echo ">>> Installing build dependencies..."

apt-get update

apt-get install -y \
    build-essential \
    wget \
    curl \
    ca-certificates \
    xz-utils \
    tar \
    bzip2 \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libffi-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libgdbm-dev \
    liblzma-dev \
    tk-dev \
    uuid-dev \
    libpq-dev \
    libldap2-dev \
    libsasl2-dev \
    libkrb5-dev

###############################################################################
# 3. Prepare CPython source
###############################################################################

echo
echo ">>> Preparing CPython ${PYTHON_VERSION}..."

mkdir -p "${BUILD_ROOT}"
cd "${BUILD_ROOT}"

ARCHIVE="Python-${PYTHON_VERSION}.tgz"
URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${ARCHIVE}"

if [ ! -f "${ARCHIVE}" ]; then
    echo
    echo ">>> Downloading:"
    echo "    ${URL}"

    curl -fL "${URL}" -o "${ARCHIVE}"
fi

echo
echo ">>> CPython archive checksum:"
sha256sum "${ARCHIVE}"

if [ ! -d "${PYTHON_SRC}" ]; then
    tar xf "${ARCHIVE}"
fi

###############################################################################
# 4. Clean previous CPython build
###############################################################################

cd "${PYTHON_SRC}"

echo
echo ">>> Cleaning CPython build..."

make distclean >/dev/null 2>&1 || true

###############################################################################
# 5. Configure
###############################################################################

echo
echo ">>> Configuring CPython..."

./configure \
    --prefix="${RUNTIME_ROOT}" \
    --enable-unicode=ucs4 \
    --with-ensurepip=no

###############################################################################
# 6. Compile
###############################################################################

echo
echo ">>> Compiling CPython..."

make -j"$(nproc)"

###############################################################################
# 7. Install runtime
###############################################################################

echo
echo ">>> Installing runtime into:"
echo "    ${RUNTIME_ROOT}"

rm -rf "${RUNTIME_ROOT}"

make install

###############################################################################
# 8. Install Python 2 compatible packaging stack
###############################################################################

echo
echo ">>> Installing pip ${PIP_VERSION}..."

cd "${BUILD_ROOT}"

GET_PIP="${BUILD_ROOT}/get-pip.py"

if [ ! -f "${GET_PIP}" ]; then
    curl -fL \
        https://bootstrap.pypa.io/pip/2.7/get-pip.py \
        -o "${GET_PIP}"
fi

run "${PYTHON}" "${GET_PIP}" \
    "pip==${PIP_VERSION}" \
    "setuptools==${SETUPTOOLS_VERSION}" \
    "wheel==${WHEEL_VERSION}"

###############################################################################
# 9. Install WAPT SERVER dependencies
###############################################################################

echo
echo "============================================================"
echo " Installing WAPT SERVER dependencies"
echo "============================================================"

run "${PIP}" install \
    --no-cache-dir \
    -r "${REPO_ROOT}/requirements-server.txt"

###############################################################################
# 10. Verify critical packages
###############################################################################

echo
echo ">>> Verifying critical packages..."

"${PYTHON}" - <<'PY'
import sys

packages = [
    "flask",
    "flask_login",
    "flask_socketio",
    "eventlet",
    "greenlet",
    "cryptography",
    "OpenSSL",
    "requests",
    "peewee",
    "psutil",
    "netifaces",
    "ldap3",
    "psycopg2",
    "ujson",
]

failed = False

for module in packages:
    try:
        __import__(module)
        print("OK  ", module)
    except Exception as e:
        print("FAIL", module, ":", repr(e))
        failed = True

if failed:
    sys.exit(1)
PY

###############################################################################
# 11. Apply WAPT cryptography compatibility patch
###############################################################################

echo
echo "============================================================"
echo " Applying WAPT cryptography patch"
echo "============================================================"

CRYPTO_X509="${RUNTIME_ROOT}/lib/python2.7/site-packages/cryptography/x509"

[ -d "${CRYPTO_X509}" ] \
    || die "cryptography/x509 directory not found: ${CRYPTO_X509}"

cp -f \
    "${REPO_ROOT}/utils/patch-cryptography/__init__.py" \
    "${CRYPTO_X509}/__init__.py"

cp -f \
    "${REPO_ROOT}/utils/patch-cryptography/verification.py" \
    "${CRYPTO_X509}/verification.py"

echo ">>> WAPT cryptography patch installed."

###############################################################################
# 12. Apply WAPT socketIO client patch if present
###############################################################################

echo
echo "============================================================"
echo " Checking WAPT socketIO compatibility patch"
echo "============================================================"

SOCKETIO_DIR="${RUNTIME_ROOT}/lib/python2.7/site-packages/socketIO_client"

if [ -d "${SOCKETIO_DIR}" ]; then

    echo ">>> socketIO_client found."

    cp -f \
        "${REPO_ROOT}/utils/patch-socketio-client-2/__init__.py" \
        "${SOCKETIO_DIR}/__init__.py"

    cp -f \
        "${REPO_ROOT}/utils/patch-socketio-client-2/transports.py" \
        "${SOCKETIO_DIR}/transports.py"

    echo ">>> WAPT socketIO patch installed."

else
    echo ">>> socketIO_client not installed."
    echo "    No socketIO-client-2 patch required for this server runtime."
fi

###############################################################################
# 13. Basic Python runtime validation
###############################################################################

echo
echo "============================================================"
echo " Python runtime validation"
echo "============================================================"

echo
echo ">>> Python:"
"${PYTHON}" --version

echo
echo ">>> Python executable:"
readlink -f "${PYTHON}"

echo
echo ">>> Python prefix:"
"${PYTHON}" -c \
    "import sys; print sys.prefix"

echo
echo ">>> Python OpenSSL:"
"${PYTHON}" -c \
    "import ssl; print ssl.OPENSSL_VERSION"

echo
echo ">>> pip:"
"${PIP}" --version

###############################################################################
# 14. WAPT server import validation
###############################################################################

echo
echo "============================================================"
echo " WAPT Server import validation"
echo "============================================================"

CONF_DIR="${RUNTIME_ROOT}/conf"
CONF_FILE="${CONF_DIR}/waptserver.ini"

mkdir -p "${CONF_DIR}"

cat > "${CONF_FILE}" <<'CONFIG'
[options]
wapt_bind_interface = 127.0.0.1
nginx_http = 80
nginx_https = 443
remote_repo_support = False
remote_repo_websockets = True
auto_create_ldap_users = True
wol_port = 9
enable_store = False
CONFIG

echo
echo ">>> Test configuration:"
cat "${CONF_FILE}"

echo
echo ">>> Importing WAPT server..."

CONFIG_FILE="${CONF_FILE}" \
PYTHONPATH="${REPO_ROOT}" \
"${PYTHON}" - <<'PY'
import waptserver.server

print("WAPT SERVER MODULE OK")
PY

###############################################################################
# 15. WAPT server component validation
###############################################################################

echo
echo ">>> Testing WAPT server components..."

CONFIG_FILE="${CONF_FILE}" \
PYTHONPATH="${REPO_ROOT}" \
"${PYTHON}" - <<'PY'
import waptserver.config
import waptserver.model
import waptserver.auth
import waptserver.tasks

print("WAPT SERVER COMPONENTS OK")
PY

###############################################################################
# 16. Socket.IO validation
###############################################################################

echo
echo ">>> Testing WAPT Socket.IO..."

CONFIG_FILE="${CONF_FILE}" \
PYTHONPATH="${REPO_ROOT}" \
"${PYTHON}" - <<'PY'
import waptserver.server_socketio

print("WAPT SOCKETIO OK")
PY

###############################################################################
# 17. WAPT crypto functional test
###############################################################################

echo
echo "============================================================"
echo " WAPT cryptographic functional test"
echo "============================================================"

CONFIG_FILE="${CONF_FILE}" \
PYTHONPATH="${REPO_ROOT}" \
"${PYTHON}" - <<'PY'
from waptcrypto import (
    SSLPrivateKey,
    SSLCertificate,
)

# CA
ca_key = SSLPrivateKey()
ca_key.create()

ca_cert = ca_key.build_sign_certificate(
    cn="WAPT Test CA",
    is_ca=True,

)

# Client
client_key = SSLPrivateKey()
client_key.create()

csr = client_key.build_csr(
    cn="WAPT Inventory Test Client"
)

client_cert = ca_cert.build_certificate_from_csr(
    csr,
    ca_key,

)

content = "WAPT inventory test"

signature = client_key.sign_content(content)

verified_cn = client_cert.verify_content(
    content,
    signature
)

print("Crypto verification:", verified_cn)

if verified_cn != "WAPT Inventory Test Client":
    raise Exception(
        "Unexpected certificate CN: %r" % verified_cn
    )

print("WAPT CRYPTO TEST PASSED")
PY

###############################################################################
# 18. Generate runtime inventory
###############################################################################

echo
echo "============================================================"
echo " Runtime inventory"
echo "============================================================"

INVENTORY="${RUNTIME_ROOT}/WAPT-runtime-inventory.txt"

{
    echo "===== WAPT PYTHON 2 RUNTIME ====="
    echo
    echo "Build date:"
    date -u
    echo
    echo "Repository:"
    git -C "${REPO_ROOT}" rev-parse --show-toplevel
    echo
    echo "Git commit:"
    git -C "${REPO_ROOT}" rev-parse HEAD
    echo
    echo "Git branch:"
    git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD
    echo
    echo "===== SYSTEM ====="
    cat /etc/debian_version
    uname -a
    echo
    echo "===== COMPILER ====="
    gcc --version | head -n 1
    echo
    echo "===== PYTHON ====="
    "${PYTHON}" --version
    "${PYTHON}" -c "import sys; print sys.prefix"
    echo
    echo "===== OPENSSL ====="
    "${PYTHON}" -c "import ssl; print ssl.OPENSSL_VERSION"
    echo
    echo "===== PIP ====="
    "${PIP}" --version
    echo
    echo "===== PACKAGES ====="
    "${PIP}" freeze
    echo
    echo "===== SIZE ====="
    du -sh "${RUNTIME_ROOT}"
    echo
    echo "===== PYTHON BINARY SHA256 ====="
    sha256sum "${PYTHON}"
} > "${INVENTORY}"

echo
echo ">>> Runtime inventory:"
cat "${INVENTORY}"

###############################################################################
# 19. Final status
###############################################################################

echo
echo "============================================================"
echo " BUILD SUCCESS"
echo "============================================================"

echo
echo "Runtime:"
echo "  ${RUNTIME_ROOT}"

echo
echo "Python:"
echo "  ${PYTHON}"

echo
echo "Inventory:"
echo "  ${INVENTORY}"

echo
echo "IMPORTANT:"
echo "  This is a transitional Python 2 compatibility runtime."
echo "  Do NOT expose it as the final security architecture."

echo
echo "All WAPT runtime tests passed."
echo
