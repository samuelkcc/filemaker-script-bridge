import Foundation

public enum ExampleScript {
    public static let fileMaker26 = """
    # AI-generated order approval example
    Set Variable [ $orderTotal ; Value: Sum ( LineItems::amount ) ]
    If [ $orderTotal > 1000 ]
        Set Variable [ $status ; Value: "needs approval" ]
        Show Custom Dialog [ Title: "Order review" ; Message: $status ]
    Else
        Set Variable [ $status ; Value: "approved" ]
    End If
    Exit Script [ Text Result: $status ]
    """
}
