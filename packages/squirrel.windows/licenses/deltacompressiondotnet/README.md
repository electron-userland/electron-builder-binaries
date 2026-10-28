# DeltaCompressionDotNet

A managed wrapper around [Microsoft's delta compression application programming interfaces](http://msdn.microsoft.com/en-us/library/bb417345.aspx).

## License

*DeltaCompressionDotNet* is licensed under the [*Microsoft Public License (MS-PL)*](http://www.microsoft.com/en-us/openness/licenses.aspx).

It's worth noting that large parts of *DeltaCompressionDotNet*'s implementation are generic (we're talking `rangeCheck`, here) and while this wrapper represents my own, original work, it would be difficult to enforce the license against anything but a slavish copy.

To this extent, the library is also licensed under the [*DBAD-PL*](http://www.dbad-license.org).

## Getting Started

[Install the *DeltaCompressionDotNet* package from NuGet](http://nuget.org/packages/DeltaCompressionDotNet/).

### Creating Deltas

    var compression = new MsDeltaCompression(); /* or PatchApiCompression(); */
    compression.CreateDelta(sourcePath, destinationPath, deltaPath);

`CreateDelta` returns `void`; if the function is not successful in creating a delta a `Win32Exception` is thrown. The `NativeErrorCode` of the exception should contain the value of `GetLastError()`, which may describe the failure.

### Applying Deltas

    var compression = new MsDeltaCompression(); /* or PatchApiCompression(); */
	compression.ApplyDelta(deltaPath, sourcePath, destinationPath);

`ApplyDelta` returns `void`; if the function is not successful in applying a delta a `Win32Exception` is thrown. The `NativeErrorCode` of the exception should contain the value of `GetLastError()`, which may describe the failure.

## Miscellany

Both `MsDeltaCompression` and `PatchApiCompression` implement `IDeltaCompression`.

*PatchAPI* (concomitant class: `PatchApiCompression`) is available from Windows 2000; *MSDelta* (concomitant class: `MsDeltaCompression`) is available from Windows Vista.

*DeltaCompressionDotNet* targets the .NET Framework 4.5, which is only available on Windows Vista and later.

Nothing prevents you from reducing the library target to a version of the .NET Framework that runs on operating systems earlier than Windows Vista, but if you're lucky enough to be using the .NET Framework 4.5 then you should prefer `MsDeltaCompression` over `PatchApiCompression` where possible.

The library is not tied to any particular architecture, the code should execute on x86, x64 and ia64.

It's unlikely that *DeltaCompressionDotNet* will work on operating systems other than Windows (à la Mono).

## Bugs/Feedback

If you encounter a scenario where the wrapping around *PatchAPI* or *MSDelta* doesn't work as you expect, you're welcome to report a bug, initiate a pull request or send an email to `t AT speot DOT is`. The latter method is likely to elicit a response, but not guaranteed.

The above applies equally for feedback.
