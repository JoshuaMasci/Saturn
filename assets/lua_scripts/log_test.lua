print("This is a lua message")

function update(dt)
    if (isControllerButtonPressed("south")) then
        print("This is a lua update dt: ", dt)
    end
end
