function FormatOutput($objects, $schemaPath) {
  Write-Debug "Resolving enums"
  If( !$Script:enums ) {
    $rawOutput = $true
    # If enums haven't been read get them and save them for later use
    $enums = Invoke-QlikGet "/qrs/about/api/enums"
    $Script:enums = $enums | Get-Member -MemberType NoteProperty | ForEach-Object { $enums.$($_.Name) }
  }
  If( !$Script:relations ) {
    # If relations haven't been read get them and save them for later use
    $Script:relations = Get-QlikRelations
  }
  foreach( $object in $objects ) {
    # Determine the object type being formatted
    If( !$schemaPath ) { $schemaPath = $object.schemaPath }
    Write-Debug "Schema path: $schemaPath"
    foreach( $prop in ( $object | Get-Member -MemberType NoteProperty ) ) {
      If( $object.$($prop.Name) -is [string] -And $object.$($prop.Name) -match $isDate ) {
        # Update any value that looks like a date to a more human readable format
        $object.$($prop.Name) = Get-Date -Format "yyyy/MM/dd HH:mm" $object.$($prop.Name)
      }
      Write-Debug "Property: $schemaPath.$($prop.Name)"
      # Find enums related to the current object property
      $enumsRelated = $Script:enums | where-object { $_.Usages -contains "$schemaPath.$($prop.Name)" }
      If( $enumsRelated ) {
        # If there is an enum for the property then resolve it
        $value = ((($enumsRelated | Select-Object -expandproperty values | Where-Object {$_ -like "$($object.$($prop.Name)):*" }) -split ":")[1]).TrimStart()
        Write-Debug "Resolving $($prop.Name) from $($object.$($prop.Name)) to $value"
        $object.$($prop.Name) = $value
      }
      # Check for relations referenced by the property
      $relatedRelations = $Script:relations -like "$schemaPath.$($prop.Name) > *"
      If( $relatedRelations ) {
        # If there are relations for the property then call self for the object
        Write-Debug "Traversing $($prop.Name)"
        $object.$($prop.Name) = FormatOutput $object.$($prop.Name) $(($relatedRelations -Split ">")[1].TrimStart())
      }
    }
  }
  return $objects
}

function GetCustomProperties($customProperties) {
  $prop = @(
    $customProperties | Where-Object {$_} | ForEach-Object {
      $val = $_ -Split "="
      $p = Get-QlikCustomProperty -filter "name eq '$($val[0])'"
      @{
        value = ($p.choiceValues -eq $val[1])[0]
        definition = $p
      }
    }
  )
  return $prop
}

function GetTags($tags) {
  $prop = @(
    $tags | Where-Object {$_} | ForEach-Object {
      $p = Get-QlikTag -filter "name eq '$_'"
      @{
        id = $p.id
      }
    }
  )
  return $prop
}

function GetUser($param) {
  if ($param -is [System.String]) {
    if ($param -match $script:guid) {
      return @{ id = $param }
    } elseif ($param -match '\w+\\\w+') {
      $parts = $param -split '\\'
      $userDirectory = $parts[0]
      $userId = $parts[1]
    } elseif ($param -match '^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$') {
      $parts = $param -split '@'
      $userId = $parts[0]
      $userDirectory = $parts[1]
    } else {
      throw 'Unrecognised format for user parameter'
    }

    Get-QlikUser -filter "userDirectory eq '$userDirectory' and userId eq '$userId'"
  } elseif ($param -is [System.Collections.Hashtable] -or $param -is [System.Management.Automation.PSCustomObject]) {
    return $param
  } else {
    throw "Invalid type for user parameter, $($param.GetType().Name)"
  }
}
