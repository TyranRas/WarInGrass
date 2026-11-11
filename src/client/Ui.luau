-- Small helpers to build the screens: labels, round frames, buttons, panels.
local Ui = {}

function Ui.circle(parent: Instance, color: Color3, position: UDim2, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Position = position
	frame.Size = size
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

-- A text that grows and shrinks with its box. Position is the middle of the text.
function Ui.label(parent: Instance, position: UDim2, size: UDim2, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = position
	text.Size = size
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = color
	text.TextStrokeTransparency = 0.3
	text.Text = ""
	text.ZIndex = 10
	text.Parent = parent
	return text
end

-- A dark box with round corners.
function Ui.panel(parent: Instance, position: UDim2, size: UDim2, z: number?): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(15, 22, 15)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.ZIndex = z or 20
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 160, 70)
	stroke.Thickness = 2
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end

local BUTTON_COLORS = {
	main = Color3.fromRGB(70, 150, 55), -- green: the main thing to do
	normal = Color3.fromRGB(55, 70, 55),
	danger = Color3.fromRGB(170, 55, 45), -- red: leave, cancel
	gold = Color3.fromRGB(200, 150, 40),
}

-- A button with round corners that lights up under the mouse.
function Ui.button(parent: Instance, text: string, position: UDim2, size: UDim2, kind: string?, onClick: () -> ()): TextButton
	local color = BUTTON_COLORS[kind or "normal"] or BUTTON_COLORS.normal
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.ZIndex = (parent:IsA("GuiObject") and parent.ZIndex or 20) + 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = button
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.15)
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = color
	end)
	button.Activated:Connect(onClick)
	button.Parent = parent
	return button
end

return Ui
