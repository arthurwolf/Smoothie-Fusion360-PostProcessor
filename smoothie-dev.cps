/**
Copyright (C) 2012-2015 by Autodesk, Inc.
All rights reserved.

Smoothie post processor configuration.

Community version ( smoothieware.org )
*/

// TODO: Shopbot line 190 : seems to handle the stuff we need to do with workpiece
// TODO: Add support for probing the surface of the part

// Basic post-processor information, this is displayed inside Fusion
description = "Smoothie Mill/Laser";
longDescription = "Generic post for Smoothie. This post supports both milling and laser cutting toolpath.";
vendor = "Smoothie";
vendorUrl = "http://smoothieware.org";
legal = "Copyright (C) 2012-2015 by Autodesk, Inc.";
certificationLevel = 2; // No idea what this is
minimumRevision = 24000; // No idea what this is

// Smoothie likes the ".gcode" file extension more than ".nc"
extension = "gcode";

// User-defined properties, with default values.
// Note you can modify these values in the post-processor configuration window :
// Right click "Setups" or a given setup, click "Post-process", then go to the "Program Settings" section of the window that appears
propertyDefinitions = {
  writeMachine:{
    title:"Write machine",
    description:"Output the machine settings in the header of the code.",
    group:0,
    type:"boolean",
    default: true
  },
  writeTools:{
    title:"Write tool list",
    description:"Output a tool list in the header of the code.",
    group:0,
    type:"boolean",
    default:true
  },
  writePart:{
    title:"Write part",
    description:"Output information about the size and position of the workpiece and fixture in the header of the code ( as uppermost and lowermost corners of the bounding boxes )",
    group:0,
    type:"boolean",
    default: true
  },
  showSequenceNumbers:{
    title:"Use sequence numbers",
    description:"Use sequence numbers for each block of outputted code ( not recommended for Smoothie ).",
    group:1,
    type:"boolean",
    default: false
  },
  sequenceNumberStart:{
    title:"Start sequence number",
    description:"The number at which to start the sequence numbers.",
    group:1,
    type:"integer",
    default: 10
  },
  sequenceNumberIncrement:{
    title:"Sequence number increment",
    description:"The amount by which the sequence number is incremented by in each block.",
    group:1,
    type:"integer",
    default: 1
  },
  useCycles:{
    title:"Use cycles",
    description:"Specifies if canned drilling cycles should be used.",
    type:"boolean",
    default: false
  },
  laserToolNumber:{
    title:"Laser tool number",
    description:"Sets the tool number used for laser cutting.",
    type:"boolean",
    default: 1
  },
  laserEtchPower:{
    title:"Laser etch power",
    description:"Sets the laser etch power.",
    type:"number",
    default: 0.1
  },
  laserPower:{
    title:"Laser power",
    description:"Sets the laser power.",
    type:"number",
    default: 1
  },
  useLaserM3M5:{
    title:"Use Laser M3/M5",
    description:"Enable to activate the laser using M3/M5.",
    type:"boolean",
    default: true
  },
  allowHelicalMoves:{
    title:"Allow Helical Moves",
    description: "Whether helical moves are output normally, or cut into as many linear segments as necessary",
    type:"boolean",
    default:true
  },
  doToolChangeInPostProcessor:{
    title:"Do tool change in Post-Processor",
    description:"Whether the details of the tool change procedures is setup in the Post-Processor itself ( supported ) or on-board Smoothieboard ( unsupported as of mid-2018, see smoothieware.org )",
    type: "boolean",
    default:true
  },
  retractBeforeSection:{
    title:"Retract before section",
    description:"Whether to retract up to a safe Z height before doing a new section",
    type: "boolean",
    default: false
  },
  initialToolDump:{
    title: "Initial tool dump",
    description: "Whether to open the tool grabbing clamp above a safe position before starting the program, in case a tool was unsafely left in the spindle",
    type: "boolean",
    default: true
  },
  initialHomeSeek:{
    title: "Initial home seek",
    description: "Whether to seek home ($H command), ie search for the endstops for each axis, before starting the program, thus ensuring machine position is known for sure",
    type: "boolean",
    default: true
  },
  initialSetZero:{
    title: "Initial set zero",
    description: "Whether to set the position at which the program starts as the zero position for the WCS. This allows for easy/fast origin setting by simply moving to the desired start point then starting the program.",
    type: "boolean",
    default: true
  }
};

// Grab the default values for all properties and store the way Fusion likes
var properties = {};
for( var property in propertyDefinitions ){
  if( propertyDefinitions.hasOwnProperty(property)){ properties[property] = propertyDefinitions[property].default; }
}

// Do we allow helical moves or not
allowHelicalMoves = properties.allowHelicalMoves;

// Use the "ascii" codepage
setCodePage("ascii");

// Smoothie can control CNC milling ( vertical or router ) as well as laser cutters, waterjets and plasma cutters
capabilities = CAPABILITY_MILLING | CAPABILITY_JET;
tolerance = spatial(0.002, MM);

// Define some resolutions
minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowedCircularPlanes = undefined; // allow any circular motion
highFeedrate = (unit == IN) ? 100 : 1000;

// Map of coolant commands
var mapCoolantTable = new Table(
  [107, 106, 106, 106, 106, 106, 106, 106, 106],
  {initial:COOLANT_OFF, force:true},
  "Invalid coolant mode"
);

// Formatting tools
// G and M Gcode formatting
var gFormat = createFormat({prefix:"G", decimals:0});
var mFormat = createFormat({prefix:"M", decimals:0});
// Parameter formatting
var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var feedFormat = createFormat({decimals:(unit == MM ? 2 : 3)});
var toolFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0});
var powerFormat = createFormat({decimals:2});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-1000
var taperFormat = createFormat({decimals:1, scale:DEG});
// Gcode output utilities
var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var zOutput = createVariable({prefix:"Z"}, xyzFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var sOutput = createVariable({prefix:"S", force:false}, rpmFormat);
var powerOutput = createVariable({prefix:"S", force:false}, powerFormat);
// Circular output
var iOutput = createReferenceVariable({prefix:"I"}, xyzFormat);
var jOutput = createReferenceVariable({prefix:"J"}, xyzFormat);
var kOutput = createReferenceVariable({prefix:"K"}, xyzFormat);
// Misc utilities
var gMotionModal = createModal({force:true}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({onchange:function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21
var gCycleModal = createModal({}, gFormat); // modal group 9 // G81, ...
var gRetractModal = createModal({}, gFormat); // modal group 10 // G98-99

// No idea what this is. Autodesk put it here so it might be important. TODO: Ask them
var WARNING_WORK_OFFSET = 0;

// Collected state
var sequenceNumber;
var currentWorkOffset;

// Create the beginning of the program
function onOpen() {

  // First line
  writeComment("Program start");

  // Output program name
  if (programName) { writeComment("Program name: " + programName); }

  // Output program comment
  if (programComment) { writeComment(programComment); }

  // Output machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();
  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine information :"));
    if (vendor     ) { writeComment("  " + localize("vendor"     ) + ": " + vendor); }
    if (model      ) { writeComment("  " + localize("model"      ) + ": " + model);}
    if (description) { writeComment("  " + localize("description") + ": " + description); }
  }

  // Output tool information
  if (properties.writeTools) {
    writeComment(localize("Tool list for this program :"));
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }
    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "  Tool T" + toolFormat.format(tool.number) + " " +
        "Diameter D=" + xyzFormat.format(tool.diameter) + " " +
        localize("CornerRadius CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }// End output tool information

  // Get part information
  var workpiece = getWorkpiece();
  var fixture = getFixture();
  var zHeight = 0;
  if( workpiece != undefined ){
    zHeight += Math.abs(workpiece.upper.z - workpiece.lower.z);
    if( properties.writePart ){ writeComment("With workpiece zHeight is " + zHeight); }
  }
  if( fixture != undefined ){
    zHeight += Math.abs(fixture.upper.z - fixture.lower.z);
    if( properties.writePart ){ writeComment("With fixture zHeight is " + zHeight); }
  }

  // Output part information
  if( properties.writePart ){
    // Output workpiece information
    if( workpiece != undefined ){
      writeComment("Workpiece information: ");
      writeComment("  Lower corner of Workpiece: " + workpiece.lower.toString());
      writeComment("  Higher corner of Workpiece: " + workpiece.upper.toString());
    }else{
      writeComment("No workpiece found");
    }

    // Output fixture information
    if( fixture != undefined ){
      writeComment("Fixture information: ");
      writeComment("  Lower corner of Fixture: " + fixture.lower.toString());
      writeComment("  Higher corner of Fixture: " + fixture.upper.toString());
    }else{
      writeComment("No fixture found");
    }

    // Output material information
    if (hasGlobalParameter("material")) {
      writeComment("Material: " + getGlobalParameter("material"));
    }

    // Output material hardness information
    if (hasGlobalParameter("material-hardness")) {
      writeComment("  Harness: " + getGlobalParameter("material-hardness"));
    }


  }// End output part information

  // Set up absolute coordinates ( http://smoothieware.org/g90 )
  writeBlock(gAbsIncModal.format(90));

  // Set up default XY plane ( http://smoothieware.org/g17 )
  writeBlock(gPlaneModal.format(17));

  // Set up units
  switch (unit) {
    case IN:
    writeBlock(gUnitModal.format(20)); // ( http://smoothieware.org/g20 )
    break;
    case MM:
    writeBlock(gUnitModal.format(21)); // ( http://smoothieware.org/g21 )
    break;
  }

  // If configured to do so, set the current position as the WCS zero
  if( properties.initialSetZero ){
    writeComment("Position at beginning of program becomes the zero for WCS");
    writeBlock(gFormat.format(10), "L20", "P1", "X0", "Y0", "Z0");
  }

  // If configured to do so, seek home at program start
  if( properties.initialHomeSeek ){
    writeComment("Seek home at program start");
    writeln("$H");
  }

  // If configured to do so, dump the tool in the spindle in case one was left there by accident
  if( properties.initialToolDump ){
    // Go to a safe Z height, safe XY place, in WCS, and dump the tool
    dumpTool();
  }


}

// This function is called for each section ( CAM operation ) in the file
function onSection() {

  // Whether to insert a tool call
  var insertToolCall = isFirstSection() || currentSection.getForceToolChange && currentSection.getForceToolChange() || (tool.number != getPreviousSection().getTool().number);

  // Specifies that the tool has been retracted to the safe plane
  var retracted = false;

  var newWorkOffset = isFirstSection() || (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() || !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());
  if (insertToolCall || newWorkOffset || newWorkPlane) {

    // stop spindle before retract during tool change
    if (insertToolCall && !isFirstSection()) {
      onCommand(COMMAND_STOP_SPINDLE);
    }

    // Retract to safe plane ( as defined by safeZHeight )
    if( properties.retractBeforeSection ){
      retracted = true;
      writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(machineConfiguration.getRetractPlane()), "F" + feedFormat.format(machineConfiguration.getAxisZ().getMaximumFeed()) );
      writeBlock(gAbsIncModal.format(90));
      zOutput.reset();
    }

  }

  // Write an empty line as a means of separating sections
  writeln("");

  // Display current section's information
  writeComment("Section number: " + currentSection.getId());
  writeComment("  Tool " + tool.getNumber() + ": " + tool.getComment() );

  // Display comments for this operation
  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {  writeComment(comment); }
  }

  // If we need to insert a tool call
  if ( insertToolCall && currentSection.type != TYPE_JET ) {

    retracted = true;

    // Stop coolant and ?? before a tool change
    onCommand(COMMAND_COOLANT_OFF);
    onCommand(COMMAND_STOP);

    // Display a warning if the tool number is too high
    if (tool.number > machineConfiguration.getNumberOfTools()) { warning(localize("Tool number (" + tool.number + " ) exceeds maximum configured number of tools ( " + machineConfiguration.getNumberOfTools() + "), see machine configuration")); }

    // Whether we should do the tool change procedure in the Post-Processor, or let Smoothie handle it
    if( properties.doToolChangeInPostProcessor ){
      // Do a tool change step by step
      // If this is the first section, we don't need to release a previous tool
      if( isFirstSection() ){
        writeComment("No need to release tool for first section ( " + currentSection.getId() + " )");
        writeComment("WARNING: No tool must be held in the spindle before starting this job");

        // Else we need to release the tool from the previous section
      }else{
        // Get the tool in the previous section
        var previous_tool = getSection(currentSection.getId()-1).getTool();
        writeComment("Releasing tool " + previous_tool.number + " after it was used in section " + (currentSection.getId()-1) );

        // Release the tool
        releaseTool(previous_tool);
        writeComment("Tool " + tool.number + " was released");

      }

      // Now that the previous tool is released, grab the new tool
      writeComment("Grabbing tool " + tool.number + " in preparation for section " + currentSection.getId());

      // Grab the tool
      grabTool(tool);
      writeComment("Tool " + tool.number + " was grabbed");

    }else{
      // Ask machine to change tool
      writeBlock("T" + toolFormat.format(tool.number));
    }

    // Write comment for this tool
    if (tool.comment) { writeComment(tool.comment); }

    // Whether we show the ZMin for each tool
    var showToolZMin = false;
    if (showToolZMin) {
      if (is3D()) {
        var numberOfSections = getNumberOfSections();
        var zRange = currentSection.getGlobalZRange();
        var number = tool.number;
        for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
          var section = getSection(i);
          if (section.getTool().number != number) {
            break;
          }
          zRange.expandToRange(section.getGlobalZRange());
        }
        writeComment(localize("ZMIN") + "=" + zRange.getMinimum());
      }
    }

  }

  // If this is a "jet"-type machine
  if (currentSection.type == TYPE_JET) {
    switch (tool.type) {
      case TOOL_LASER_CUTTER:
      break;
      default:
      error(localize("The CNC does not support the required tool/process. Only laser cutting is supported."));
      return;
    }

    var toolNumber = properties.laserToolNumber; // laser
    switch (currentSection.jetMode) {
      case JET_MODE_THROUGH:
      break;
      case JET_MODE_ETCHING:
      break;
      case JET_MODE_VAPORIZE:
      break;
      default:
      error(localize("Unsupported cutting mode."));
      return;
    }

    // Output Tool change word
    writeBlock("T" + toolFormat.format(toolNumber));

  }

  // Spindle speed
  if ((currentSection.type != TYPE_JET) && (insertToolCall || isFirstSection() || (rpmFormat.areDifferent(tool.spindleRPM, sOutput.getCurrent())) || (tool.clockwise != getPreviousSection().getTool().clockwise))) {
    if (currentSection.type != TYPE_JET) {
      if (tool.spindleRPM <= 0) { error(localize("Spindle speed out of range.")); }
      if (tool.spindleRPM > 999999) { warning(localize("Spindle speed exceeds maximum value.")); }
    }
    if (!tool.clockwise) { error(localize("CNC does not support CCW spindle rotation.")); return; }
    writeBlock(mFormat.format(tool.clockwise ? 3 : 4), sOutput.format(tool.spindleRPM));
  }

}

function onClose() {
  onCommand(COMMAND_COOLANT_OFF);

  //if (properties.useLaserM3M5 && (currentSection.type == TYPE_JET) && (tool.type == TOOL_LASER_CUTTER)) {
    writeBlock(mFormat.format(5)); // deactivate laser or spindle
  //}

  // Release tool after last section
  writeComment("Releasing tool " + tool.number + " at end of program after section " + (currentSection.getId()) );

  // Release the tool
  releaseTool(tool);
  writeComment("Tool " + tool.number + " was released");

  // Retract to safe plane ( as defined by safeZHeight )
  retracted = true;
  writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(machineConfiguration.getRetractPlane()), "F" + feedFormat.format(machineConfiguration.getAxisZ().getMaximumFeed()) );
  writeBlock(gAbsIncModal.format(90));
  zOutput.reset();

  if (!machineConfiguration.hasHomePositionX() && !machineConfiguration.hasHomePositionY()) {
    //writeBlock(gFormat.format(28), gAbsIncModal.format(91), "X" + xyzFormat.format(0), "Y" + xyzFormat.format(0)); // return to home
  }

  writeComment("Program end");


}

// Grab a tool from the tool rack
function grabTool(tool){

  // Open the seal valve
  writeBlock(mFormat.format(1001));
  
  // Open the dust removal valve
  writeBlock(mFormat.format(1007));

  // Go to the Z safe height ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(machineConfiguration.getRetractPlane()), "F" + feedFormat.format(machineConfiguration.getAxisZ().getMaximumFeed())); // TODO: Make configurable

  // Go in front of the tool in X ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "X" + Math.round((96-65) + Math.round(xyzFormat.format(tool.number * 65))), "F" + feedFormat.format(machineConfiguration.getAxisX().getMaximumFeed())); // TODO: Make configurable

  // Go above the tool in Y ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Y" + xyzFormat.format(968), "F" + feedFormat.format(machineConfiguration.getAxisY().getMaximumFeed())); // TODO: Make configurable

  // Go down right above the tool in Z ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(115), "F" + feedFormat.format(machineConfiguration.getAxisZ().getMaximumFeed())); // TODO: Make configurable

  // Turn the air on to open the tool clamp
  writeBlock(mFormat.format(1003));
  writeBlock(mFormat.format(1006));

  // Wait for air to open the clamp
  onDwell(5);

  // Go down where the tool clamp can grab the tool in Z ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(91), "F" + feedFormat.format(machineConfiguration.getAxisZ().getMaximumFeed())); // TODO: Make configurable

  // Turn the air off to close the tool clamp
  writeBlock(mFormat.format(1004));
  writeBlock(mFormat.format(1005));

  // Wait for air pressure to decrease so the tool clamp closes
  onDwell(5);

  // Close the dust valve and the seal valve
  writeBlock(mFormat.format(1008));
  writeBlock(mFormat.format(1002));
  
  // Move out of the tool holder in Y so we can then go up with the tool grabbed
  writeBlock(gFormat.format(53), gFormat.format(0), "Y" + xyzFormat.format(968-30), "F" + feedFormat.format(machineConfiguration.getAxisY().getMaximumFeed())); // TODO: Make configurable

  // Go to the Z safe height ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(machineConfiguration.getRetractPlane()), "F" + feedFormat.format(machineConfiguration.getAxisZ().getMaximumFeed())); // TODO: Make configurable

}

// Release a tool to the tool rack
function releaseTool(tool){

  // Open the seal valve
  writeBlock(mFormat.format(1001));
  
  // Open the dust removal valve
  writeBlock(mFormat.format(1007));

  // Go to the Z safe height ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(machineConfiguration.getRetractPlane()), "F" + feedFormat.format(machineConfiguration.getAxisZ().getMaximumFeed())); // TODO: Make configurable

  // Go in front of the tool in X ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "X" + Math.round((96-65) + Math.round(xyzFormat.format(tool.number * 65))), "F" + feedFormat.format(machineConfiguration.getAxisX().getMaximumFeed())); // TODO: Make configurable

  // Go above the tool in Y ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Y" + xyzFormat.format(968-30), "F" + feedFormat.format(machineConfiguration.getAxisY().getMaximumFeed())); // TODO: Make configurable

  // Align with the tool holder in Z ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(92), "F" + feedFormat.format(machineConfiguration.getAxisZ().getMaximumFeed())); // TODO: Make configurable

  // Push tool into tool holder in Y ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Y" + xyzFormat.format(968), "F" + feedFormat.format(machineConfiguration.getAxisY().getMaximumFeed())); // TODO: Make configurable

  // Turn the air on to open the tool clamp
  writeBlock(mFormat.format(1003));
  writeBlock(mFormat.format(1006));

  // Wait for air to open the clamp
  onDwell(5);

  // Go to the Z safe height, leaving the tool behind ( machine coordinates )
  writeComment("Start tool up procedure");
  var zfeed = machineConfiguration.getAxisZ().getMaximumFeed();
  var zstart = 92;
  var ztop = machineConfiguration.getRetractPlane();
  // G91 G2 J2 Z1 G90
  for( var h = 0.5; h <= 20 ; h++){
    var z = 0-(zstart+(h*3));
    writeBlock(gFormat.format(91), gPlaneModal.format(17), gMotionModal.format(2), "Z" + xyzFormat.format(0.5), "J" + xyzFormat.format(h/20), gFormat.format(90));
  }
  writeBlock(gFormat.format(53), gMotionModal.format(0), "Z" + xyzFormat.format(ztop), "F" + feedFormat.format(zfeed));
  writeComment("Stop tool up procedure");


  // Turn the air off to close the tool clamp
  writeBlock(mFormat.format(1004));
  writeBlock(mFormat.format(1005));

  // Wait for air pressure to decrease so the tool clamp closes
  onDwell(5);

  // Close the dust valve and the seal valve
  writeBlock(mFormat.format(1008));
  writeBlock(mFormat.format(1002));

}


// Release a tool to the tool dumping zone
function dumpTool(){

  // Open the seal valve
  writeBlock(mFormat.format(1001));
  
  // Open the dust removal valve
  writeBlock(mFormat.format(1007));

  // Go to the Z safe height ( machine coordinates )
  writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(machineConfiguration.getRetractPlane()), "F" + feedFormat.format(machineConfiguration.getAxisZ().getMaximumFeed()));

  // Go to a safe dumping place
  writeBlock(gFormat.format(53), gFormat.format(0), "X" + xyzFormat.format(0), "Y" + xyzFormat.format(0), "F" + feedFormat.format(Math.min(machineConfiguration.getAxisX().getMaximumFeed(),machineConfiguration.getAxisY().getMaximumFeed()))); // TODO: Make configurable

  // Turn the air on to open the tool clamp
  writeBlock(mFormat.format(1003));
  writeBlock(mFormat.format(1006));

  // Wait for air to open the clamp
  onDwell(5);

  // Turn the air off to close the tool clamp
  writeBlock(mFormat.format(1004));
  writeBlock(mFormat.format(1005));

  // Wait for air pressure to decrease so the tool clamp closes
  onDwell(5);

  // Close the dust valve and the seal valve
  writeBlock(mFormat.format(1008));
  writeBlock(mFormat.format(1002));
}



// Output spindle speed change
function onSpindleSpeed(spindleSpeed) {
  // only for milling
  writeBlock(sOutput.format(spindleSpeed));
}

function onCycle() {
  writeBlock(gPlaneModal.format(17));
}

function getCommonCycle(x, y, z, r) {
  forceXYZ();
  return [xOutput.format(x), yOutput.format(y),zOutput.format(z),"R" + xyzFormat.format(r)];
}

function onCyclePoint(x, y, z) {
  if (currentSection.type == TYPE_JET) {
    error(localize("Canned cycles are not allowed when using laser."));
    return;
  }

  if (!properties.useCycles) {
    expandCyclePoint(x, y, z);
    return;
  }

  if (isFirstCyclePoint()) {
    repositionToCycleClearance(cycle, x, y, z);

    // return to initial Z which is clearance plane and set absolute mode

    var F = cycle.feedrate;
    var P = (cycle.dwell == 0) ? 0 : clamp(0.001, cycle.dwell, 99999.999); // in seconds

    switch (cycleType) {
      case "drilling":
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(81),
        getCommonCycle(x, y, z, cycle.retract),
        feedOutput.format(F)
      );
      break;
      case "counter-boring":
      if (P > 0) {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(82),
          getCommonCycle(x, y, z, cycle.retract),
          "S" + secFormat.format(P), // not optional
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(81),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
      case "chip-breaking":
      expandCyclePoint(x, y, z);
      break;
      case "deep-drilling":
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(83),
          getCommonCycle(x, y, z, cycle.retract),
          "Q" + xyzFormat.format(cycle.incrementalDepth),
          feedOutput.format(F)
        );
      }
      break;
      default:
      expandCyclePoint(x, y, z);
    }
  } else {
    if (cycleExpanded) {
      expandCyclePoint(x, y, z);
    } else {
      var _x = xOutput.format(x);
      var _y = yOutput.format(y);
      if (!_x && !_y) {
        xOutput.reset(); // at least one axis is required
        _x = xOutput.format(x);
      }
      writeBlock(_x, _y);
    }
  }
}

function onCycleEnd() {
  if (!cycleExpanded) {
    writeBlock(gCycleModal.format(80));
    zOutput.reset();
  }
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

var shapeArea = 0;
var shapePerimeter = 0;
var shapeSide = "inner";
var cuttingSequence = "";

function onParameter(name, value) {
  if ((name == "action") && (value == "pierce")) {
    // add delay if desired
  } else if (name == "shapeArea") {
    shapeArea = value;
  } else if (name == "shapePerimeter") {
    shapePerimeter = value;
  } else if (name == "shapeSide") {
    shapeSide = value;
  } else if (name == "beginSequence") {
    if (value == "piercing") {
      if (cuttingSequence != "piercing") {
        if (properties.allowHeadSwitches) {
          // Allow head to be switched here
        }
      }
    } else if (value == "cutting") {
      if (cuttingSequence == "piercing") {
        if (properties.allowHeadSwitches) {
          // Allow head to be switched here
        }
      }
    }
    cuttingSequence = value;
  }
}


var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_SPINDLE_CLOCKWISE:3,
  COMMAND_STOP_SPINDLE:5
};

function onCommand(command) {
  switch (command) {
    case COMMAND_START_SPINDLE:
    if (!tool.clockwise) {
      error(localize("CNC does not support CCW spindle rotation."));
      return;
    }
    onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
    return;
    case COMMAND_POWER_ON:
    return;
    case COMMAND_POWER_OFF:
    return;
    case COMMAND_COOLANT_ON:
    writeBlock(mFormat.format(106)); // fan on
    return;
    case COMMAND_COOLANT_OFF:
    writeBlock(mFormat.format(107)); // fan off
    return;
    case COMMAND_LOCK_MULTI_AXIS:
    return;
    case COMMAND_UNLOCK_MULTI_AXIS:
    return;
    case COMMAND_BREAK_CONTROL:
    return;
    case COMMAND_TOOL_MEASURE:
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  writeBlock(gPlaneModal.format(17));

  if (properties.useLaserM3M5 && (currentSection.type == TYPE_JET) && (tool.type == TOOL_LASER_CUTTER)) {
    writeBlock(mFormat.format(5)); // deactivate laser
  }

  forceAny();
}



// Utility function to display a comment
function onComment(message) {
  var comments = String(message).split(";");
  for (comment in comments) {
    writeComment(comments[comment]);
  }
}


// Utility function to force output of X, Y, and Z.
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

// Utility function to force output of X, Y, Z, and F on next output.
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

/** Returns the power for the given spindle speed. */
function getPower() {
  switch (currentSection.jetMode) {
    case JET_MODE_THROUGH:
    return properties.laserPower;
    case JET_MODE_ETCHING:
    return properties.laserEtchPower;
    case JET_MODE_VAPORIZE:
    default:
    error(localize("Laser cutting mode is not supported."));
  }
  return 0;
}


function onPower(power) {
  powerOutput.reset();
  // writeBlock(powerOutput.format(power ? getPower() : 0));
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(1), x, y, z, feedOutput.format(highFeedrate), conditional(currentSection.type == TYPE_JET, powerOutput.format(0)));
    // feedOutput.reset();
  }
}


function onLinear(_x, _y, _z, feed) {
  // at least one axis is required
  if (pendingRadiusCompensation >= 0) {
    // ensure that we end at desired position when compensation is turned off
    xOutput.reset();
    yOutput.reset();
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode is not supported."));
      return;
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f, conditional(currentSection.type == TYPE_JET, powerOutput.format(power ? getPower() : 0)));
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f, conditional(currentSection.type == TYPE_JET, powerOutput.format(power ? getPower() : 0)));
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  error(localize("Multi-axis motion is not supported."));
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  error(localize("Multi-axis motion is not supported."));
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  // one of X/Y and I/J are required and likewise

  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    if (isHelical()) {
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
      case PLANE_XY:
      writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed), conditional(currentSection.type == TYPE_JET, powerOutput.format(power ? getPower() : 0)));
      gMotionModal.reset();
      break;
      case PLANE_ZX:
      writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed), conditional(currentSection.type == TYPE_JET, powerOutput.format(power ? getPower() : 0)));
      gMotionModal.reset();
      break;
      case PLANE_YZ:
      writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), yOutput.format(y), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed), conditional(currentSection.type == TYPE_JET, powerOutput.format(power ? getPower() : 0)));
      gMotionModal.reset();
      break;
      default:
      linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
      case PLANE_XY:
      writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed), conditional(currentSection.type == TYPE_JET, powerOutput.format(power ? getPower() : 0)));
      gMotionModal.reset();
      break;
      case PLANE_ZX:
      writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed), conditional(currentSection.type == TYPE_JET, powerOutput.format(power ? getPower() : 0)));
      gMotionModal.reset();
      break;
      case PLANE_YZ:
      writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed), conditional(currentSection.type == TYPE_JET, powerOutput.format(power ? getPower() : 0)));
      gMotionModal.reset();
      break;
      default:
      linearize(tolerance);
    }
  }
}


// Writes the specified block.
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}

// Remove any () from comments
function formatComment(text) {
  return "; " + String(text).replace(/[\(\)]/g, "");
}

// Output a comment.
function writeComment(text) {
  writeln(formatComment(text));
}


// Do a "dwell" ( wait "S" seconds )
function onDwell(seconds) {
  if (seconds > 99999.999 || seconds < 0) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeBlock(gFormat.format(4), "S" + secFormat.format(seconds));
}
