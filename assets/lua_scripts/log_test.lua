function applyDeadZone(value, dead_zone)
    if math.abs(value) < dead_zone then
        return 0.0
    else
        local sign = value > 0 and 1 or -1
        local magnitude = (math.abs(value) - dead_zone) / (1.0 - dead_zone)
        return sign * math.min(magnitude, 1.0)
    end
end

function buttonsToAxis(pos_state, neg_state)
    if pos_state and not neg_state then
        return 1.0
    elseif not pos_state and neg_state then
        return -1.0
    else
        return 0.0;
    end
end

if isControllerButtonPressed("south") then
    print("South button pressed")
end

local dead_zone = 0.1;
local move_speed = 5.0
local forward_backward = applyDeadZone(getControllerAxis("left_y"), dead_zone) * -1.0
local left_right = applyDeadZone(getControllerAxis("left_x"), dead_zone) * -1.0
local up_down = buttonsToAxis(isControllerButtonDown("right_shoulder"), isControllerButtonDown("left_shoulder"))

setEntityLinearVelocity(left_right * move_speed, up_down * move_speed, forward_backward * move_speed)
setEntityAngularVelocity(0.0, 0.0, 0.0)

local some_vector = vec4.new(0.0, 1.0, 2.0);
print("Some Vector: ", getX(some_vector), ", ", getY(some_vector), ", ", getZ(some_vector), ", ", getW(some_vector), ", ")
