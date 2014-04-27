require 'spec_helper'
#require 'ruby-debug'

feature "Reimbursements", "" do
  fixtures :all

  scenario "Full reimbursement process", :js => true do
    sign_in_as_user(users(:luke))
    visit request_path(requests(:luke_for_yavin))
    click_link "Ask for reimbursement"

    # Request creation
    page.should have_content "reimbursement was successfully created"
    fill_in "reimbursement_description", :with => "Hey, I destroyed the Death Star so I deserve the reimbursement."
    fill_in "holder", :with => "Owen Lars"
    fill_in "financial institution", :with => "Tatooine Saving Bank"
    fill_in "account IBAN", :with => "TT123456789012"
    fill_in "account BIC/SWIFT code", :with => "0987654"
    within(:xpath, "//tbody[@id='expenses']//tr[td[contains(.,'Gas')]]") do
      find('input').set "120"
    end
    within(:xpath, "//tbody[@id='expenses']//tr[td[contains(.,'Droid rental')]]") do
      find('input').set "50"
    end
    click_button "Update reimbursement"
    page.should have_content "reimbursement was successfully updated"
    @reimbursement = Reimbursement.order(:created_at).last

    # Failed submission
    click_link "Action"
    click_link "Submit"
    fill_in "notes", :with => "I've not fulfilled one of the amounts"
    click_button "submit"
    page.should have_content "Something went wrong. Unable to submit."
    page.should have_content "under modification, not submitted"
    page.should have_content "Expenses are missing or invalid"

    # Correct the request
    close_modal_dialog
    click_link "Edit"
    page.should have_content "Edit reimbursement"
    within(:xpath, "//tbody[@id='expenses']//tr[td[contains(.,'Lodging')]]") do
      find('input').set "100"
    end
    click_button "Update reimbursement"
    page.should have_content "reimbursement was successfully updated"

    # The signature notification (and the link) should be there...
    page.should have_content "An updated signed version of the reimbursement request is required"
    page.should have_link "Attach signed document"
    page.should have_link "Download printable version"
    # ..but our hero decides to ignore it
    click_link "Action"
    click_link "Submit"
    fill_in "notes", :with => "I don't sign autograph for free."
    click_button "submit"
    page.should have_content "Unable to submit."
    page.should have_content "Signed acceptance can't be blank"
    page.should_not have_content "Expenses are missing or invalid" # Not longer the problem

    # No way. Time to attach
    visit request_reimbursement_path(@reimbursement.request)
    click_link "Attach signed document"
    page.should have_content "Print it, sign it, scan the signed version and upload it using the form below"
    attach_file "acceptance_file", Rails.root.join("spec", "support", "files", "scan001.pdf")
    click_button "Attach signed document"
    page.should have_content "scan001.pdf"
    # Submit again
    click_link "Action"
    click_link "Submit"
    fill_in "notes", :with => "Ok, now all the information is there."
    click_button "submit"
    page.should have_content "Successfully submitted."
    page.should have_content "from incomplete to submitted"
    page.should have_content "is being evaluated"
    page.should_not have_link "Attach signed document"

    # Testing audits, just in case
    @reimbursement.audits.last.user.should == users(:luke)
    @reimbursement.expenses.first.audits.last.user.should == users(:luke)

    # Log in as tspmember
    click_link "Log out"
    find_reimbursement_as(users(:tspmember), @reimbursement)
    page.should_not have_link "Attach signed document"

    # Rolling back
    click_link "Action"
    click_link "Roll Back"
    fill_in "notes", :with => "Sorry Mr. Idestroyedthedeathstar: no invoices, no money"
    click_button "roll back"
    page.should have_content "Successfully rolled back."
    page.should have_content "requester must update the reimbursement with all the relevant information"
    page.should_not have_link "Attach signed document"

    # Log in as requester
    click_link "Log out"
    find_reimbursement_as(users(:luke), @reimbursement)
    page.should have_link "Attach signed document"

    # Add links and attachments
    click_link "Edit"
    page.should have_content "Edit reimbursement"
    click_link "add link"
    within(:xpath, "//tbody[@id='links']//tr[@class='nested-fields'][last()]") do
      find('input[name$="[title]"]').set "Video recording of my intervention"
      find('input[name$="[url]"]').set "http://www.youtube.com/watch?v=DOFgFAcGHQc"
    end
    click_link "add attachment"
    show_jasny_file_inputs "#attachments input[name$='[file]']"
    within(:xpath, "//tbody[@id='attachments']//tr[@class='nested-fields'][last()]") do
      find('input[name$="[title]"]').set "Lodging receipt"
      find('input[name$="[file]"]').set Rails.root.join("spec", "support", "files", "scan001.pdf")
    end
    click_link "add attachment"
    show_jasny_file_inputs "#attachments input[name$='[file]']"
    within(:xpath, "//tbody[@id='attachments']//tr[@class='nested-fields'][last()]") do
      find('input[name$="[title]"]').set "Gas receipt"
      find('input[name$="[file]"]').set Rails.root.join("spec", "support", "files", "scan001.pdf")
    end
    click_button "Update reimbursement"
    page.should have_content "reimbursement was successfully updated"

    # And submit again
    click_link "Action"
    click_link "Submit"
    fill_in "notes", :with => "Here you are the invoices. Make sure you also watch the video."
    click_button "submit"
    page.should have_content "Successfully submitted."

    # Log in as tspmember
    click_link "Log out"
    find_reimbursement_as(users(:tspmember), @reimbursement)

    # Approving if all invoices are there
    page.should have_content "Video recording"
    page.should have_content "Lodging receipt"
    page.should have_content "Gas receipt"
    click_link "Action"
    click_link "Approve"
    fill_in "notes", :with => "Everything ok know."
    click_button "approve"
    page.should have_content "Successfully approved."
    page.should have_content "will be now processed by the administrative"

    # Log in as administrative
    click_link "Log out"
    find_reimbursement_as(users(:administrative), @reimbursement)
    # Process the reimbursement
    click_link "Action"
    click_link "Process"
    fill_in "notes", :with => "Every ok. Sending to accounting dept."
    click_button "process"
    page.should have_content "Payment processed"
    page.should have_content "payment is ongoing"
    # And mark it as payed
    click_link "Action"
    click_link "Confirm"
    click_button "confirm"
    page.should have_content "Confirmation processed"
    page.should have_content "process have ended succesfully"
  end
end
