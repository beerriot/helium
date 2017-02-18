-- Helium reporting queue, to prevent waking up the antenna for every reading.
-- Example usage:
--   -- report after five readings accumulate,
--   -- readings are on the "t" and "p" ports, each of whis is a float
--   Q = queue:new(5, {{"t", "f"}, {"p", "f"}})
--   Q:addEntry(1, {20, 998}) -- temp: 20, pressure: 998
--   Q:addEntry(2, {21, 1000})
--   Q:addEntry(3, {20, 997})
--   Q:addEntry(4, {21, 999})
--   Q:addEntry(5, {19, 998})
--   -- he.send is called 2 ports * 5 readings = 10 times during the last call
--   -- i.e. he.send("t", 1, "f", 20)
--   --      he.send("p", 1, "f", 998)
--   --      he.send("t", 2, "f", 21)
--   --      he.send("p", 2, "f", 1000)
--   --      ...

queue = {}

-- Create a new queue that send results to helium every maxEntries entries.
-- entryDefs is a list of {name, type} tables
function queue:new(maxEntries, entryDefs)
   assert(entryDefs)
   for k,v in ipairs(entryDefs) do
      assert(v.name and v.type)
   end
   
   local o = {
      maxEntries = maxEntries or 1,
      entryDefs = entryDefs,
      entries = {},
      entryCount = 0,
   }
   setmetatable(o, self)
   self.__index = self
   return o
end

-- Add an entry to the queue. values is a list of values, given in the
-- same order as entryDefs was given to the constructor.
function queue:addEntry(time, values)
   assert(time and values)

   self.entryCount = self.entryCount + 1
   self.entries[self.entryCount] = {
      time = time,
      values = values
   }

   if self.entryCount >= self.maxEntries then
      self:_reportEntries()
      self.entryCount = 0
      -- we'll just let addEntry overwrite instead of forcibly clearing
   end
end

function queue:_reportEntries()
   for i=1,self.entryCount do
      for k,v in ipairs(self.entryDefs) do
         he.send(v.name, self.entries[i].time,
                 v.type, self.entries[i].values[k])
      end
   end
end
