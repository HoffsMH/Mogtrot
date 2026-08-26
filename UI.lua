local _, ns = ...

ns.UI = {
	Pad = 10,
	CloseButtonInset = 4,
	-- Outfit actions are unavailable in combat, so protected rows add restrictions
	-- without enabling an action the insecure template cannot perform.
	ActionButtonTemplate = "InsecureActionButtonTemplate",
	MainWindow = {
		Width = 300,
		RowHeight = 30,
		HeaderHeight = 22,
		SearchRowHeight = 44,
		IconSize = 24,
		Indent = 14,
		HeaderButtonHeight = 20,
		HeaderControlIconSize = 14,
		HeaderControlGap = 4,
		MaxVisibleRows = 40,
		MinListHeight = 200,
		MaxListHeight = 900,
		DefaultListRows = 21,
	},
}
