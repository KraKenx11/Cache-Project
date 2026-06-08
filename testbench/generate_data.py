import random

NUM_BLOCKS = 262144 # 2^18 blocuri pentru a umple memoria de 8 MiB
BLOCK_SIZE_BITS = 256
HEX_CHARS = BLOCK_SIZE_BITS // 4

filename = "mem_data.txt"

print(f"Generez {NUM_BLOCKS} de blocuri random (8 MiB).")

with open(filename, "w") as f:
    for _ in range(NUM_BLOCKS):
        # Genereaza un numar random pe 256 de biti
        rand_val = random.getrandbits(BLOCK_SIZE_BITS)
        hex_str = f"{rand_val:0{HEX_CHARS}X}\n"
        f.write(hex_str)

print(f"Succes! Datele au fost salvate in fisierul '{filename}'.")