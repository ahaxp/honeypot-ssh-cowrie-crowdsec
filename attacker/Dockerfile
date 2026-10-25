FROM kalilinux/kali-rolling
RUN apt-get update && apt-get install -y --no-install-recommends hydra && rm -rf /var/lib/apt/lists/*
COPY pass.txt /pass.txt
CMD ["sleep", "infinity"]
