#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright Clairvoyant 2017

# Function to discover basic OS details.
discover_os() {
  if command -v lsb_release >/dev/null; then
    # CentOS, Ubuntu, RedHatEnterpriseServer, Debian, SUSE LINUX
    # shellcheck disable=SC2034
    OS=$(lsb_release -is)
    # CentOS= 6.10, 7.2.1511, Ubuntu= 14.04, RHEL= 6.10, 7.5, SLES= 11
    # shellcheck disable=SC2034
    OSVER=$(lsb_release -rs)
    # 7, 14
    # shellcheck disable=SC2034
    OSREL=$(echo "$OSVER" | awk -F. '{print $1}')
    # Ubuntu= trusty, wheezy, CentOS= Final, RHEL= Santiago, Maipo, SLES= n/a
    # shellcheck disable=SC2034
    OSNAME=$(lsb_release -cs)
  else
    if [ -f /etc/redhat-release ]; then
      if [ -f /etc/centos-release ]; then
        # shellcheck disable=SC2034
        OS=CentOS
        # 7.5.1804.4.el7.centos, 6.10.el6.centos.12.3
        # shellcheck disable=SC2034
        OSVER=$(rpm -qf /etc/centos-release --qf='%{VERSION}.%{RELEASE}\n' | awk -F. '{print $1"."$2}')
        # shellcheck disable=SC2034
        OSREL=$(rpm -qf /etc/centos-release --qf='%{VERSION}\n')
      else
        # shellcheck disable=SC2034
        OS=RedHatEnterpriseServer
        # 7.5, 6Server
        # shellcheck disable=SC2034
        OSVER=$(rpm -qf /etc/redhat-release --qf='%{VERSION}\n')
        if [ "$OSVER" == "6Server" ]; then
          # shellcheck disable=SC2034
          OSVER=$(rpm -qf /etc/redhat-release --qf='%{RELEASE}\n' | awk -F. '{print $1"."$2}')
          # shellcheck disable=SC2034
          OSNAME=Santiago
        else
          # shellcheck disable=SC2034
          OSNAME=Maipo
        fi
        # shellcheck disable=SC2034
        OSREL=$(echo "$OSVER" | awk -F. '{print $1}')
      fi
    elif [ -f /etc/SuSE-release ]; then
      if grep -q "^SUSE Linux Enterprise Server" /etc/SuSE-release; then
        # shellcheck disable=SC2034
        OS="SUSE LINUX"
      fi
      # shellcheck disable=SC2034
      OSVER=$(rpm -qf /etc/SuSE-release --qf='%{VERSION}\n' | awk -F. '{print $1}')
      # shellcheck disable=SC2034
      OSREL=$(rpm -qf /etc/SuSE-release --qf='%{VERSION}\n' | awk -F. '{print $1}')
      # shellcheck disable=SC2034
      OSNAME="n/a"
    fi
  fi
}

echo "********************************************************************************"
echo "*** $(basename "$0")"
echo "********************************************************************************"
# Check to see if we are on a supported OS.
discover_os
if [ "$OS" != RedHatEnterpriseServer ] && [ "$OS" != CentOS ]; then
#if [ "$OS" != RedHatEnterpriseServer ] && [ "$OS" != CentOS ] && [ "$OS" != Debian ] && [ "$OS" != Ubuntu ]; then
  echo "ERROR: Unsupported OS."
  exit 3
fi

echo "Installing PostgreSQL..."
DATE=$(date '+%Y%m%d%H%M%S')

if [ "$OS" == RedHatEnterpriseServer ] || [ "$OS" == CentOS ]; then
  yum -y -e1 -d1 install postgresql-server

  postgresql-setup initdb

  if [ ! -f /var/lib/pgsql/data/pg_hba.conf-orig ]; then
    cp -p /var/lib/pgsql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf-orig
  else
    cp -p /var/lib/pgsql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf."${DATE}"
  fi
  # shellcheck disable=SC1004
  sed -e '/# CLAIRVOYANT$/d' \
      -e '/^host\s*all\s*all\s*127.0.0.1\/32\s*\sident$/i\
host    all             all             0.0.0.0/0               md5 # CLAIRVOYANT' \
      -i /var/lib/pgsql/data/pg_hba.conf
#host    all             all             127.0.0.1/32            md5 # CLAIRVOYANT' \

  # https://www.cloudera.com/documentation/enterprise/latest/topics/cm_ig_extrnl_pstgrs.html
  if [ ! -f /var/lib/pgsql/data/postgresql.conf-orig ]; then
    cp -p /var/lib/pgsql/data/postgresql.conf /var/lib/pgsql/data/postgresql.conf-orig
  else
    cp -p /var/lib/pgsql/data/postgresql.conf /var/lib/pgsql/data/postgresql.conf."${DATE}"
  fi
  sed -e '/# CLAIRVOYANT$/d' \
      -e '/^max_connections/d' \
      -e '/^listen_addresses/d' \
      -e '/^shared_buffers/d' \
      -e '/^wal_buffers/d' \
      -e '/^checkpoint_segments/d' \
      -e '/^checkpoint_completion_target/d' \
      -e '/^standard_conforming_strings/d' \
      -i /var/lib/pgsql/data/postgresql.conf
  cat <<EOF >>/var/lib/pgsql/data/postgresql.conf
max_connections = 500                                            # CLAIRVOYANT
listen_addresses = '*'                                           # CLAIRVOYANT
shared_buffers = 256MB                                           # CLAIRVOYANT
wal_buffers = 8MB                                                # CLAIRVOYANT
checkpoint_segments = 16                                         # CLAIRVOYANT
checkpoint_completion_target = 0.9                               # CLAIRVOYANT
# This is needed to make Hive work with Postgresql 9.1 and above # CLAIRVOYANT
# See OPSAPS-11795                                               # CLAIRVOYANT
standard_conforming_strings = off                                # CLAIRVOYANT
EOF

  service postgresql restart
  chkconfig postgresql on

  _PASS=$(apg -a 1 -M NCL -m 20 -x 20 -n 1)
  if [ -z "$_PASS" ]; then
    _PASS=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c 20;echo)
  fi
  echo "****************************************"
  echo "****************************************"
  echo "****************************************"
  echo "*** SAVE THIS PASSWORD"
  echo "postgres : ${_PASS}"
  echo "****************************************"
  echo "****************************************"
  echo "****************************************"

  # shellcheck disable=SC1117
  su - postgres -c 'psql' <<EOF
\password
$_PASS
$_PASS
\q
EOF
elif [ "$OS" == Debian ] || [ "$OS" == Ubuntu ]; then
  :
fi

