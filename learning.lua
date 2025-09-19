print("Hello, World!")
print("This is a Lua script.")
print("Let's do some math: 2 + 2 =", 2 + 2)
print("Lua version:", _VERSION)
print("Lua supports functions:")

local Name="bob"

function greet(Name)
    return "Hello, " .. Name .. "!"
end
print(greet("Alice"))

print("Lua tables are versatile:")
local t = {key1 = "value1", key2 = "value2"}
for k, v in pairs(t) do
    print(k, v)
end

print("Lua supports loops:")
for i = 1, 5 do
    print("Iteration:", i)
end

print("Lua supports conditionals:")
local num = 10      
if num > 5 then
    print(num, "is greater than 5")
else
    print(num, "is not greater than 5")
end

print("Lua supports string manipulation:")
local str = "Hello, Lua!"
print("Original string:", str)
print("Uppercase:", string.upper(str))  
print("Lowercase:", string.lower(str))
print("Substring (1-5):", string.sub(str, 1, 5))            

print("Lua supports math operations:")
local a, b = 15, 4
print("a =", a, ", b =", b)         
print("Addition:", a + b)
print("Subtraction:", a - b)
print("Multiplication:", a * b)
print("Division:", a / b)           
print("Modulus:", a % b)
print("Exponentiation:", a ^ b)
print("Floor Division:", math.floor(a / b))

print("Lua supports tables as arrays:")
local arr = {10, 20, 30, 40, 50}
for i = 1, #arr do
    print("Element " .. i .. ":", arr[i])
end 

print("Lua supports metatables:")
local mt = {
    __add = function(t1, t2)
        return {value = t1.value + t2.value}
    end
}   
local obj1 = {value = 5}
local obj2 = {value = 10}       
setmetatable(obj1, mt)
setmetatable(obj2, mt)
local obj3 = obj1 + obj2        
print("obj1 + obj2 =", obj3.value)

print("Lua supports coroutines:")
local co = coroutine.create(function()
    for i = 1, 3 do
        print("Coroutine iteration:", i)
        coroutine.yield()
    end
end)        
coroutine.resume(co)
coroutine.resume(co)
coroutine.resume(co)
coroutine.resume(co)

print("Lua supports modules:")
local mymodule = {}
function mymodule.sayHello(name)
    return "Hello, " .. name .. " from module!"
end 
print(mymodule.sayHello("Bob"))

print("Lua supports file I/O:")
local file = io.open("example.txt", "w")
if file then
    file:write("This is a test file.\nLua file I/O is easy!\n")
    file:close()
else
    print("Error: Could not open file for writing.")
end
local file = io.open("example.txt", "r")
if file then
    for line in file:lines() do
        print("Read from file:", line)
    end
    file:close()
else
    print("Error: Could not open file for reading.")
end

