import matplotlib.pyplot as plt

# Data
apple_years = [2019, 2020, 2021, 2022, 2023, 2024, 2025]
apple_tops = [6, 11, 15.8, 17, 35, 35, 38]

qualcomm_years = [2021, 2022, 2023, 2024, 2025]
qualcomm_tops = [26, 32, 40, 45, 65]

plt.figure(figsize=(10, 5))

# Apple line
plt.plot(apple_years, apple_tops, marker='o', linewidth=2, label="Apple A-series (iPhone)")

# Qualcomm line
plt.plot(qualcomm_years, qualcomm_tops, marker='o', linewidth=2, label="Qualcomm Snapdragon 8-series")

plt.title("Evolution of Mobile NPU Performance (TOPS/s)")
plt.xlabel("Year")
plt.ylabel("NPU Performance (TOPS)")
plt.grid(True, linestyle='--', alpha=0.4)
plt.legend()

# Save for LaTeX
plt.savefig("tops_growth.pdf", bbox_inches='tight')
plt.savefig("tops_growth.png", dpi=300, bbox_inches='tight')

plt.show()
