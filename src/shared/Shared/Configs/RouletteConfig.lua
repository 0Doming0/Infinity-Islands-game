return table.freeze({
	BasicWheel = table.freeze({
		DisplayName = "Roleta Basica",
		CostType = "Coins",
		CostAmount = 100,
		DuplicateCompensation = 75,
		Rewards = table.freeze({
			table.freeze({ RewardType = "Coins", RewardId = "Coins", Amount = 50, Weight = 40 }),
			table.freeze({ RewardType = "Coins", RewardId = "Coins", Amount = 150, Weight = 30 }),
			table.freeze({ RewardType = "Sword", RewardId = "BronzeSword", Amount = 1, Weight = 15 }),
			table.freeze({ RewardType = "Companion", RewardId = "GreenSlime", Amount = 1, Weight = 10 }),
			table.freeze({ RewardType = "Ticket", RewardId = "LuckyWheelSpin", Amount = 1, Weight = 5 }),
		}),
	}),
})
