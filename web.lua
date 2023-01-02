export type ResultCallback = (result: Result) -> ()

export type Web = {
  get: (url: string, resultCallback: ResultCallback?) -> Request;
  post: (url: string, data: string, resultCallback: ResultCallback?) -> Request;
  postForm: (url: string, form: {}, resultCallback: ResultCallback?) -> Request;
  put: (url: string, data: string, resultCallback: ResultCallback?) -> Request;
  request: (url: string, method: string, headers: {}, contentType: string, contentData: string, resultCallback: ResultCallback?) -> Request;
  clearCookieCache: () -> ();
  clearUrlCookieCache: (url: string) -> ();
  accessDenied: boolean;
}

export type Request = {
  abort: () -> boolean;
  uploadProgress: number;
  downloadProgress: number;
  ready: boolean;
  result: Result | nil;
}

export type Result = {
  ok: boolean;
  contentType: string;
  errorMessage: string;
  errorType: string;
  isError: boolean;
  responseCode: number;
  text: string;
  type: string;
}

local function eventToResult(e: WifiWebResponseEvent): Result
  return {
    ok = e.ResponseCode == 200,
    contentType = e.ContentType,
    errorMessage = e.ErrorMessage,
    errorType = e.ErrorType,
    isError = e.IsError,
    responseCode = e.ResponseCode,
    text = e.Text,
    type = e.Type
  }
end

local messages = {
  freeChannelNotFound = "Couldn't find a free event channel in %s; Use a different CPU or specify an event channel.",
  eventChannelInUseWarning = "Warning: replacing registered module %s on %s event channel %d with module %s. Change the event channel if this was unintentional.",
  eventChannelTooLow = "Event channel must be bigger than or equal to 1, given: %d",
  eventChannelTooHigh = "Can't use event channel %d; %s only has %d channels.",
  wifiChipNotFound = "Default Wifi chip (Wifi0) not found; add it to your gadget or specify another Wifi chip.",
  cpuNotFound = "Default CPU not (CPU0) not found; add it to your gadget or specify another CPU.",
  readOnly = "%s is readonly."
}

local function throwError(template: string, ...)
  error(string.format(template, ...))
end

local function printWarning(template: string, ...)
  logWarning(string.format(template, ...))
end

local function findFreeEventChannel(cpu: CPU)
  local foundChannel: number | nil = nil
  for channel = 1, #cpu.EventChannels do
    if cpu.EventChannels[channel] == nil then foundChannel = channel break end
  end
  if foundChannel == nil then throwError(messages.freeChannelNotFound, tostring(cpu)) end
  return foundChannel
end

local function checkForRegisteredModule(cpu: CPU, wifi: Wifi, eventChannel: number)
  local registeredModule = cpu.EventChannels[eventChannel]

  if registeredModule ~= nil and registeredModule ~= wifi then
    printWarning(messages.eventChannelInUseWarning, tostring(registeredModule), tostring(cpu), eventChannel, tostring(wifi))
  end
end

local function checkCpuChannelCount(cpu: CPU, eventChannel: number)
  if eventChannel < 1 then 
    throwError(messages.eventChannelTooLow, eventChannel)
  elseif eventChannel > #cpu.EventChannels then 
    throwError(messages.eventChannelTooHigh, eventChannel, tostring(cpu), #cpu.EventChannels)
  end
end

local function setGlobalEventChannelFunction(eventChannel: number, func: (...any) -> ())
  getfenv(0)["eventChannel"..eventChannel] = func
end

local function create(wifi: Wifi?, cpu: CPU?, eventChannel: number?): Web
  local wifi = wifi or gdt.Wifi0 or throwError(messages.wifiChipNotFound)
  local cpu = cpu or gdt.CPU0 or throwError(messages.cpuNotFound)
  local eventChannel = eventChannel or findFreeEventChannel(cpu)

  checkCpuChannelCount(cpu, eventChannel)
  checkForRegisteredModule(cpu, wifi, eventChannel)

  local requests: {{handle: number, resultCallback: ResultCallback}} = {}

  setGlobalEventChannelFunction(
    eventChannel,
    function(_, event: WifiWebResponseEvent) 
      requests[event.RequestHandle].resultCallback(eventToResult(event))
      requests[event.RequestHandle] = nil
    end
  )
  
  cpu.EventChannels[eventChannel] = wifi

  local function addRequest(handle: number, resultCallback: ResultCallback?): Request
    local status: "inProgress" | "completed" | "aborted" = "inProgress"
    local result: Result | nil;
    
    requests[handle] = {
      handle = handle,
      resultCallback = function(r) 
        status = "completed"
        result = r
        if resultCallback then resultCallback(r) end
      end
    }
    local proto = {
      abort = function() 
        status = "aborted"
        return wifi:WebAbort(handle) 
      end
    }
    local mt = {
      __index = function(_, key: string | number) 
        if proto[key] ~= nil then return proto[key] end
        if key == "uploadProgress" then return wifi:GetWebUploadProgress(handle) end
        if key == "downloadProgress" then return wifi:GetWebDownloadProgress(handle) end
        if key == "ready" then return status ~= "inProgress" end
        if key == "result" then return result end
      end,
      __newindex = function() throwError(messages.readOnly, "Request") end,
    }
    return setmetatable({}, mt) :: any
  end
  
  local proto = {
    get = function(url: string, resultCallback: ResultCallback?): Request
      return addRequest(wifi:WebGet(url), resultCallback)
    end,
    post = function(url: string, data: string, resultCallback: ResultCallback?): Request
      return addRequest(wifi:WebPostData(url, data), resultCallback)
    end,
    postForm = function(url: string, form: {}, resultCallback: ResultCallback?): Request
      return addRequest(wifi:WebPostForm(url, form), resultCallback)
    end,
    put = function(url: string, data: string, resultCallback: ResultCallback?): Request
      return addRequest(wifi:WebPutData(url, data), resultCallback)
    end,
    request = function(url: string, method: string, headers: {}, contentType: string, contentData: string, resultCallback: ResultCallback?): Request
      return addRequest(wifi:WebCustomRequest(url, method, headers, contentType, contentData), resultCallback)
    end,
    clearCookieCache = function(): ()
      wifi:ClearCookieCache()    
    end,
    clearUrlCookieCache = function(url: string): ()
      wifi:ClearUrlCookieCache(url)
    end
  }
  
  local mt = {
    __index = function(_, key: string | number)
      if proto[key] ~= nil then return proto[key] end
      if key == "accessDenied" then return wifi.AccessDenied end
    end,
    __newindex = function() throwError(messages.readOnly, "Web") end
  }
    
  return setmetatable({}, mt) :: any
end

return table.freeze{create = create}