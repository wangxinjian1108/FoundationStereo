export DIR=$(pwd)
cd docker && docker build --network host -t foundation_stereo .
bash run_container.sh
cd /
git clone https://github.com/onnx/onnx-tensorrt.git
cd onnx-tensorrt
python3 setup.py install
apt-get install -y libnvinfer-dispatch10 libnvinfer-bin tensorrt
cd $DIR