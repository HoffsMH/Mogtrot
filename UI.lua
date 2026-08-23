local _, ns = ...

ns.UI = {
	Pad = 10,
	-- Outfit actions are unavailable in combat, so protected rows add restrictions
	-- without enabling an action the insecure template cannot perform.
	ActionButtonTemplate = "InsecureActionButtonTemplate",
	MainWindow = {
		Width = 300,
		RowHeight = 30,
		HeaderHeight = 22,
		SearchRowHeight = 26,
		IconSize = 24,
		Indent = 14,
		HeaderButtonHeight = 20,
		MaxVisibleRows = 40,
		MinListHeight = 200,
		MaxListHeight = 900,
		DefaultListRows = 21,
	},
}
