# Ubuntu 24 + systemd + OpenVPN + stunnel + FastAPI panel.
# Run with: host networking, /dev/net/tun, NET_ADMIN, cgroup (see docker-compose.yml).
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssl openvpn stunnel4 easy-rsa \
    iputils-ping \
    python3 python3-pip \
    systemd systemd-sysv \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/panel

COPY VERSION .
COPY requirements.txt .
RUN pip3 install --break-system-packages --no-cache-dir -r requirements.txt

COPY app ./app
COPY scripts ./scripts
COPY systemd/ /etc/systemd/system/

RUN chmod +x /opt/panel/scripts/*.sh \
  && ln -sf /etc/systemd/system/ovpn-data-init.service /etc/systemd/system/multi-user.target.wants/ovpn-data-init.service \
  && ln -sf /etc/systemd/system/openvpn-ovpn.service /etc/systemd/system/multi-user.target.wants/openvpn-ovpn.service \
  && ln -sf /etc/systemd/system/stunnel-ovpn.service /etc/systemd/system/multi-user.target.wants/stunnel-ovpn.service \
  && ln -sf /etc/systemd/system/ovpn-panel.service /etc/systemd/system/multi-user.target.wants/ovpn-panel.service

COPY docker/defaults /etc/default/ovpn-panel

STOPSIGNAL SIGRTMIN+3

VOLUME ["/data"]

EXPOSE 443 8139

CMD ["/opt/panel/scripts/docker-cmd.sh"]
