# On part de l'image RunPod officielle que tu as spécifiée
FROM runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404

# Configuration pour éviter les interactions lors des installations
ENV DEBIAN_FRONTEND=noninteractive

# Updating apt and installing dependencies (pciutils, lshw)..."
RUN apt-get update
RUN apt-get install -y pciutils lshw

# --- 1. Installation d'Ollama ---
RUN curl -fsSL https://ollama.com/install.sh | sh

# --- 2. Installation de Open-WebUI ---
# On utilise pip. Open-WebUI a besoin de Python 3.11+, 
# l'image ubuntu24.04 a généralement une version récente.
RUN pip install open-webui

# --- 3. Configuration des Variables d'Environnement ---
# Pour qu'Ollama écoute sur toutes les interfaces (important dans Docker)
ENV OLLAMA_HOST=0.0.0.0
# Port par défaut d'Open-WebUI
ENV PORT=8080
# Variable pour ton modèle par défaut (tu pourras la changer sur RunPod)
ENV MODEL_TO_LOAD="llama3"

# --- 4. PERSISTANCE DES DONNÉES ---
# On dit à Ollama de stocker les modèles dans le volume persistant
ENV OLLAMA_MODELS="/workspace/ollama/models"

# On dit à Open-WebUI de stocker sa base de données (chats, users) dans le volume persistant
ENV DATA_DIR="/workspace/open-webui/data"

# --- 5. Mise en place du script de démarrage ---
COPY start.sh /start.sh
RUN chmod +x /start.sh

# On expose le port 8080 (WebUI) et 11434 (API Ollama)
EXPOSE 8080 11434

# --- 5. Commande de lancement ---
# C'est ce qui se lance quand le Pod démarre
CMD ["/start.sh"]