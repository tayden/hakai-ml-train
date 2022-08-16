ARG VERSION=1.12.1-cuda11.3-cudnn8-runtime
FROM pytorch/pytorch:$VERSION

ENV PYTHONPATH /opt/code:$PYTHONPATH
WORKDIR /opt/code

# Install dependancies
COPY requirements.txt .
RUN apt-get update && \
    apt-get upgrade --assume-yes && \
    apt-get install --assume-yes git gcc rsync && \
    pip install -r requirements.txt

# Copy the code to the image
COPY . .
WORKDIR /opt/code/src

# Run python by default
CMD "python"
