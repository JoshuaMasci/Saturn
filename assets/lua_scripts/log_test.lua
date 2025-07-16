if isControllerButtonPressed("south") then
    print("South button pressed")
end

local value = getControllerAxis("left_y")
if math.abs(value) > 0.1 then
    print("Left Stick: ", value)
end
