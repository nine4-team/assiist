from setuptools import setup, find_packages

setup(
    name="assiist_back_end",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        # Your requirements will be read from requirements.txt
        line.strip()
        for line in open("requirements.txt")
        if line.strip() and not line.startswith("#")
    ],
) 